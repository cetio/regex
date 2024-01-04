import std.stdio;
import std.typecons;
import std.bitmanip;
import std.string;
import std.conv;
import std.ascii;
import std.algorithm;

void main()
{
    auto regex = new Regex(r"^a%1%1", "");
    foreach (element; regex.elements)
        writeln(element);
    writeln(regex.match("aaa"));
}

public enum : ubyte
{
    BAD,
    /// `(?...)`
    LOOKAHEAD,
    /// `(...<...)`
    LOOKBEHIND,
    /// `[...]`
    CHARACTERS,
    /// `^`
    ANCHOR_START,
    /// `$`
    ANCHOR_END,
    /// `(...)`
    GROUP,
    /// `.`
    ANY,
    /// ~`\gn`~ or `$n` (group) or `%n` (absolute)
    REFERENCE,
    // Not used! Comments don't need to be parsed!
    // (?#...)
    //COMMENT
    /// `\K` `\Kn`
    RESET
}

public enum : ubyte
{
    NONE = 0,
    /// `|`
    ALTERNATE = 1,
    /// `[^...]`
    EXCLUSIONARY = 2,
    /// `{...}`
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
    /// `(?:...)`
    NONCAPTURE = 8,
    /// `(...!...)`
    NEGATIVE = 8,
    /// `...?`
    LAZY = 8,
    /// `...+`
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

string marketEscapes(string str)
{
    string result;
    foreach (c; str)
    {
        switch (c)
        {
            case '\n': result ~= "\\n"; break;
            case '\r': result ~= "\\r"; break;
            case '\t': result ~= "\\t"; break;
            case '\a': result ~= "\\a"; break;
            case '\b': result ~= "\\b"; break;
            case '\f': result ~= "\\f"; break;
            case '\v': result ~= "\\v"; break;
            case '\0': result ~= "\\0"; break;
            default: result ~= c; break;
        }
    }
    return result;
}


private struct Element
{
public:
align(1):
    /// What kind of element is this?
    /// eg: `CHARACTERS`
    ubyte token;
    /// What are the special modifiers of this element?
    /// eg: `EXCLUSIONARY`
    ubyte modifiers;
    /// Number of characters or elements to be read during fulfillment
    /// eg: `3`
    uint length;
    union
    {
        /// Characters mapped (like in a character set or literal)
        /// eg: `&cache.table[0]`
        char* str;
        /// Elements mapped (like in a group or reference)
        Element* elements;
    }
    /// Minimum times to require fulfillment
    /// eg: `1`
    uint min;
    /// Maximum times to allow fulfillment
    /// eg: `1`
    uint max;

    this (ubyte token, char* str)
    {
        this.token = token;
        this.str = str;
    }

    bool fulfilled(Regex regex, string text, ref uint index)
    {
        switch (token)
        {
            case BAD:
                throw new Exception("Cannot fulfill a bad token, fix your regex or live with the consequences of your actions.");
            case LOOKAHEAD:
                return false;
            case LOOKBEHIND:
                return false;
            case CHARACTERS:
                bool match;
                foreach (i; 0..length)
                {
                    if (str[i] == text[index])
                        match = true;
                }
                return (modifiers & EXCLUSIONARY) != 0 ? !match : match;
                break;
            case ANCHOR_START:
                return index == 0 || ((regex.flags & MULTILINE) != 0 && 
                    (text[index - 1] == '\r' || text[index - 1] == '\n' || text[index - 1] == '\f'));
            case ANCHOR_END:
                return index >= text.length || ((regex.flags & MULTILINE) != 0 && 
                    (text[index + 1] == '\r' || text[index + 1] == '\n' || text[index + 1] == '\f' || text[index + 1] == '\0'));
            case GROUP:
                foreach (i; 0..length)
                {
                    if (!elements[i].fulfilled(regex, text, index))
                        return false;
                }
                return true;
            case ANY:
                return ((regex.flags & SINGLELINE) != 0 || (text[index] != '\r' && text[index] != '\n' && text[index] != '\f'));
            case REFERENCE:
                return elements[0].fulfilled(regex, text, index);
            default:
                return false;
        }
    }

    string toString() const
    {
        string token;
        string modifiers;
        switch (this.token)
        {
            case BAD: token = "BAD"; break;
            case LOOKAHEAD: token = "LOOKAHEAD"; break;
            case LOOKBEHIND: token = "LOOKBEHIND"; break;
            case CHARACTERS: token = "CHARACTERS"; break;
            case ANCHOR_START: token = "ANCHOR_START"; break;
            case ANCHOR_END: token = "ANCHOR_END"; break;
            case GROUP: token = "GROUP"; break;
            case ANY: token = "ANY"; break;
            case REFERENCE: token = "REFERENCE"; break;
            case RESET: token = "RESET"; break;
            default: token = this.token.to!string; break;
        }

        if (this.modifiers == 0)
            modifiers = "NONE";

        if ((this.modifiers & ALTERNATE) != 0)
            modifiers ~= modifiers.length != 0 
                ? " | ALTERNATE" 
                : "ALTERNATE";

        if ((this.modifiers & EXCLUSIONARY) != 0)
            modifiers ~= modifiers.length != 0 
                ? " | EXCLUSIONARY" 
                : "EXCLUSIONARY";

        if ((this.modifiers & QUANTIFIED) != 0)
            modifiers ~= modifiers.length != 0 
                ? " | QUANTIFIED" 
                : "QUANTIFIED";

        if ((this.modifiers & NONCAPTURE) != 0)
            modifiers ~= this.token == GROUP 
                ? modifiers.length != 0 
                    ? " | NEGATIVE" 
                    : "NEGATIVE" 
                : modifiers.length != 0 
                    ? " | NONCAPTURE" 
                    : "NONCAPTURE";
        
        if ((this.modifiers & LAZY) != 0)
            modifiers ~= modifiers.length != 0 
                ? " | LAZY"
                : "LAZY";
        
        if ((this.modifiers & GREEDY) != 0)
            modifiers ~= modifiers.length != 0 
                ? " | GREEDY"
                : "GREEDY";

        return "\x1b[36m"~token~" "~modifiers~"\x1b[0m "~length.to!string~" [ onion: \x1b[36m"~(length == 0 ? "NULL" : str[0..length].to!string.marketEscapes())~"\x1b[0m ] "~min.to!string~" "~max.to!string;
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
                        elements[$-1].min = 1;
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
                    element.min = 1;
                    element.max = 1;
                    break;
                case '[':
                    element.token = CHARACTERS;
                    element.min = 1;
                    element.max = 1;
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
                case '%':
                    if (i + 1 < pattern.length && pattern[i + 1].isDigit)
                    {
                        string rid;
                        while (i + 1 < pattern.length && pattern[i + 1].isDigit)
                            rid ~= pattern[++i];
                        uint id = rid.to!uint;

                        if (elements.length > id)
                        {
                            element.token = REFERENCE;
                            element.length = 1;
                            element.elements = &elements[id];
                        }
                        break;
                    }
                    break;
                case '$':
                    if (i + 1 < pattern.length && pattern[i + 1].isDigit)
                    {
                        string rid;
                        while (i + 1 < pattern.length && pattern[i + 1].isDigit)
                            rid ~= pattern[++i];
                        uint id = rid.to!uint;
                        uint visits;
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
                    // Will not be adding support for \gn
                    // Expected to use $n
                    if (c == '\\' && i + 1 < pattern.length)
                    {
                        if (pattern[i..(i + 2)] == "\\K")
                        {
                            i++;
                            element.token = RESET;
                            if (i + 1 < pattern.length && pattern[i + 1].isDigit)
                            {
                                string rid;
                                while (i + 1 < pattern.length && pattern[i + 1].isDigit)
                                    rid ~= pattern[++i];
                                uint id = rid.to!uint;
                                uint visits;
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
                            Tuple!(char*, uint) ins = cache.insert(pattern[i..(++i + 1)]);
                            element.str = ins[0];
                            element.length = ins[1];
                            element.min = 1;
                            element.max = 1;
                            if (pattern[i].isUpper)
                                element.modifiers |= EXCLUSIONARY;
                        }
                    }
                    else
                    {
                        element.str = cache.insert(c)[0];
                        element.length = 1;
                        element.min = 1;
                        element.max = 1;
                    }
                    break;
            }
            elements ~= element;
        }
    }

    string match(string text)
    { 
        string match;
        uint ti;
        uint ei;
        for (;ei < elements.length;)
        {
            Element element = elements[ei];
            if (element.token != ANCHOR_END && ti >= text.length)
                return null;
            
            uint tci = ti;
            if (element.fulfilled(this, text, ti))
            {
                // temporary fix!
                if (element.token == REFERENCE)
                    ti += element.elements[0].min;

                match ~= text[tci..(element.min != 0 ? ++ti : ti)];
                ei++;
            }
            else if (element.token == RESET)
            {
                match = null;
            }
            else if ((element.modifiers & ALTERNATE) == 0)
            {
                if (!elements[0].fulfilled(this, text, ti))
                    ti++;
                
                match = null;
                ei = 0;
            }
        }
        return match;
    }
}