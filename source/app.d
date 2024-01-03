import std.stdio;
import std.typecons;
import std.bitmanip;
import std.string;
import std.conv;
import std.ascii;
import std.algorithm;

void main()
{
	auto regex = new Regex(r"[abc]+", "");
	writeln(regex.match("ababbcc"));
}

public enum : ubyte
{
	BAD,
    // (?...)
    LOOKAHEAD,
    // (...<...)
    LOOKBEHIND,
    // [...]
    CHARACTERS,
    // ^
    ANCHOR_START,
    // $
    ANCHOR_END,
    // (...)
    GROUP,
    // .
    ANY,
    // Refers to a group. ie: \gn or $n
    // Also be known as a backref or a jump
    REFERENCE,
    // Not used! Comments don't need to be parsed!
    // (?#...)
    //COMMENT
	RESET,
}

public enum : ubyte
{
    NONE = 0,
	// |
	ALTERNATE = 1,
    // [^...]
    EXCLUSIONARY = 2,
    // {...}
    QUANTIFIED = 4,
    // *
    //GREEDY = 8,
    // +
    //MANY = 16,
    // ?
    //OPTIONAL = 32,
    // Now defaults to POSITIVE/CAPTURE if set to NONE
    // (...=...)
    // Also (...) (capture group)
    //CAPTURE = 64,
    //POSITIVE = 64,
    // (...!...)
    // Also (?:...) (non capture group)
    NONCAPTURE = 8,
    NEGATIVE = 8,
	LAZY = 8,
	GREEDY = 16
}

public enum : ubyte
{
    // Match more than once
    GLOBAL = 2,
    // ^ & $ match start & end
    MULTILINE = 4,
    // Case insensitive
    INSENSITIVE = 8,
    // Ignore whitespace
    EXTENDED = 16,
    // . matches \r\n\f
    SINGLELINE = 32
}

private struct Element
{
public:
    align(1):
    ubyte token;
	ubyte modifiers;
    uint length;
    union
    {
        char* str;
        Element* elements;
    }
    uint min = 1;
    uint max = 1;

    this (ubyte token, char* str)
    {
        this.token = token;
        this.str = str;
    }
}

private alias cache = Cache!();
private template Cache()
{
protected:
    char[] table = [ 0 ];
    Tuple!(char*, uint)[string] lookups;

private:
    static this()
    {
        lookups["\\w"] = insert("a-zA-Z0-9_");
        lookups["\\d"] = insert("0-9");
        lookups["\\s"] = insert(" \t\r\n\f");
        lookups["\\h"] = insert(" \t");
        lookups["\\v"] = insert("\v");
        lookups["\\b"] = insert("\b");
        lookups["\\a"] = insert("\a");
		lookups["\\0"] = insert("\0");
    }

    Tuple!(char*, uint) insert(string pattern)
    {
        if (pattern in lookups)
            return lookups[pattern];

        char* cur = &table[$-1] + char.sizeof;
        uint curlen = cast(uint)table.length;
        for (int i; i < pattern.length; i++)
        {
            // Escape chars (does not do any actual validity checking, can escape anything)
            if (pattern[i] == '\\')
            {
                // Checks for special escapes
                if (i + 1 < pattern.length && pattern[i..(i + 1)] in lookups)
                {
                    auto tup = lookups[pattern[i..++i]];
                    pattern ~= tup[0][0..tup[1]];
                }

                continue;
            }
            else if (i + 1 < pattern.length && pattern[i + 1] == '-')
            {
                // Could hypothetically implement a check for if there is only 1 unexpanded pattern
                // and if so, simply do a lookup for that, but it seems highly inefficient
                if (i + 4 < pattern.length && pattern[i + 3] == '\\')
                {
                    lookups[pattern[i..(i + 4)]] = Tuple!(char*, uint)(&table[$-1], (pattern[i + 3] + 1) - pattern[i]);
                    // Iterate set (a-\z would expand to alpha)
                    foreach (char c; pattern[i]..(pattern[i += 3] + 1))
                        table ~= c;
                }
                else
                {
                    lookups[pattern[i..(i + 3)]] = Tuple!(char*, uint)(&table[$-1], (pattern[i + 2] + 1) - pattern[i]);
                    // Iterate set (a-z would expand to alpha)
                    foreach (char c; pattern[i]..(pattern[i += 2] + 1))
                        table ~= c;
                }
            }
            else
            {
                table ~= pattern[i];
            }
        }

        return lookups[pattern] = Tuple!(char*, uint)(cur, cast(uint)(table.length - curlen));
    }

    Tuple!(char*, uint) insert(char c)
    {
        foreach (uint i; 0..cast(uint)table.length)
        {
            if (table[i] == c)
                return Tuple!(char*, uint)(&table[i], 1);
        }

        table ~= c;
        return Tuple!(char*, uint)(&table[$-1], 1);
    }
}

bool mayQuantify(Element element)
{
	return (element.modifiers & QUANTIFIED) == 0;
}

string getArgument(string pattern, int start, char opener, char closer)
{
	int openers = 1;
	foreach (i; (start + 1)..pattern.length)
	{
		if (pattern[i] == opener)
			openers++;
		else if (pattern[i] == closer)
			openers--;
		
		if (openers == 0)
			return pattern[(start + 1)..i];
	}
	return pattern[(start + 1)..pattern.length];
}

public class Regex
{
protected:
    Element[] elements;
	ubyte flags;

public:
    this(string pattern, string flags)
    {
		for (int i; i < pattern.length; i++)
		{
			Element element;
			char c = pattern[i];
			switch (c)
			{
				case '+':
					if (elements[$-1].mayQuantify)
					{
						elements[$-1].max = uint.max;
						elements[$-1].modifiers |= QUANTIFIED;
					}
					else
					{
						elements[$-1].modifiers |= GREEDY;
					}
					break;
				case '*':
					if (!elements[$-1].mayQuantify)
						continue;

					elements[$-1].min = 0;
					elements[$-1].max = uint.max;
					elements[$-1].modifiers |= QUANTIFIED;
					break;
				case '?':
					if (elements[$-1].mayQuantify)
					{
						elements[$-1].min = 0;
						elements[$-1].max = 1;
						elements[$-1].modifiers |= QUANTIFIED;
					}
					else 
					{
						elements[$-1].modifiers |= LAZY;
					}
					break;
				case '{':
					if (!elements[$-1].mayQuantify)
						continue;

					string arg = pattern.getArgument(i, '{', '}');
					string[] args = arg.split("..");
					if (args.length == 1)
					{
						elements[$-1].min = args[0].to!uint;
						elements[$-1].max = args[0].to!uint;
					}
					else if (args.length == 2)
					{
						elements[$-1].min = args[0].to!uint;
						elements[$-1].max = args[1].to!uint;
					}
					i += arg.length + 1;
					elements[$-1].modifiers |= QUANTIFIED;
					break;
				case '|':
					elements[$-1].modifiers |= ALTERNATE;
					break;
				case '.':
					element.token = ANY;
					break;
				case '[':
					element.token = CHARACTERS;
					if (i + 1 < pattern.length && pattern[i + 1] == '^')
					{
						element.modifiers |= EXCLUSIONARY;
						i++;
					}
					string arg = pattern.getArgument(i, '[', ']');
					Tuple!(char*, uint) ins = cache.insert(arg);
					element.str = ins[0];
					element.length = ins[1];
					i += arg.length + 1;
					break;
				case '^':
					element.token = ANCHOR_START;
					break;
				case '$':
					if (i + 1 < pattern.length && pattern[i + 1].isDigit)
					{
						string rid;
						while (i + 1 < pattern.length && pattern[i + 1].isDigit)
							rid ~= pattern[++i];
						uint id = rid.to!uint;
						int visits;
						foreach (ii; 0..elements.length)
					    {
							if (elements[ii].token == GROUP && visits++ == id)
							{
								element.token = REFERENCE;
								element.length = 1;
								element.elements = &elements[ii];
							}
						}
						break;
					}
					element.token = ANCHOR_END;
					break;
				default:
					element.token = CHARACTERS;
					element.length = 1;
					// Will not be adding support for \gn
					// Expected to use $n
					if (c == '\\' && i + 1 < pattern.length)
					{
						if (i + 1 < pattern.length && pattern[i + 1] == 'K')
						{
							element.token = RESET;
							if (++i + 1 < pattern.length && pattern[i + 1].isDigit)
							{
								string rid;
								while (i + 1 < pattern.length && pattern[i + 1].isDigit)
									rid ~= pattern[++i];
								uint id = rid.to!uint;
								int visits;
								foreach (ii; 0..elements.length)
								{
									if (elements[ii].token == GROUP && visits++ == id)
									{
										element.length = 1;
										element.elements = &elements[ii];
									}
								}
							}
							break;
						}
						else
						{
							element.str = cache.insert(pattern[i..++i])[0];
							if (pattern[i].isUpper)
								element.modifiers |= EXCLUSIONARY;
						}
					}
					else
					{
						element.str = cache.insert(c)[0];
					}
					break;
			}
			if (element.token != BAD)
				elements ~= element;
		}
    }

	string match(string text)
	{
		int i;
		string match;
		for (int ii; ii < text.length; ii++)
		{
			Element element = elements[i];
			ulong m = ii + element.min;
			ulong r = ii + element.max;
			for (;ii < r; ii++)
			{
				/* if (ii >= m)
					break; */

				if (ii >= text.length)
				{
					if (ii < m)
						match = null;
					break;
				}

				switch (element.token)
				{
					case CHARACTERS:
						bool fail = true;
						for (int iii; iii < element.length; iii++)
						{
							if (text[ii] == element.str[iii])
								fail = false;
						}

						if (fail && ii < m)
							return null;
						else
							match ~= text[ii];
						break;
					case ANCHOR_START:
						if (ii != 0 && ((flags & MULTILINE) == 0 || ii < 2 || 
							(text[ii - 2..ii] != "\r" && text[ii - 2..ii] != "\n" && text[ii - 2..ii] != "\f")))
							return null;
						break;
					default:
						break;
				}
			}
			if (++i < elements.length)
				return match;
		}
		return match;
	}
}