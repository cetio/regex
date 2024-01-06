import std.stdio;
import std.typecons;
import std.bitmanip;
import std.string;
import std.conv;
import std.ascii;
import std.algorithm;

void main()
{
    // fix later!
    // [\w.]+
    // \w{3}.txt
    writeln(regex!(r"\w{3}", GLOBAL).match!("abc"));
    writeln(new Regex(r"[\w]{2}", GLOBAL).match("hey, I just met you, and this is crazy but here's my number, so call me, maybe"));
    /* foreach (element; regex.elements)
        writeln(element);
    writeln(regex.match("aaa")); */
}

public enum : ubyte
{
    BAD,
    /// `(?...)`
    /// Matches group ahead
    LOOK_AHEAD,
    /// `(...<...)`
    /// Matches group behind
    LOOK_BEHIND,
    /// `[...]`
    /// Stores a set of characters (matches any)
    CHARACTERS,
    /// `^`
    /// Matches only if at the start of a line or the full text
    ANCHOR_START,
    /// `$`
    /// Matches only if at the end of a line or the full text
    ANCHOR_END,
    /// `(...)`
    /// Stores a set of elements
    GROUP,
    /// `.`
    /// Matches any character
    ANY,
    /// ~`\gn`~ or `$n` (group) or `%n` (absolute)
    /// Refers to a group or element
    REFERENCE,
    // Not used! Comments don't need to be parsed!
    // (?#...)
    //COMMENT
    /// `\K` `\Kn`
    /// Resets match or group match
    RESET,
    /// `n->` or `|->`
    /// Moves the current text position forward
    PUSHFW,
    /// `<-n` or `<-|`
    /// Moves the current text position backward
    PUSHBW
}

public enum : ubyte
{
    /// No special rules, matches until the next element can match
    NONE = 0,
    /// `|`
    /// If fails, the next element will attempt to match instead
    ALTERNATE = 1,
    /// `[^...]`
    /// Matches only if no characters in the set match
    EXCLUSIONARY = 2,
    /// `{...}`
    /// Has min/max
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
    /// Acts as a group but does not capture match
    NONCAPTURE = 8,
    /// `(...!...)`
    /// Matches if not matched
    NEGATIVE = 8,
    /// `...?`
    /// Matches as few times as possible
    LAZY = 8,
    /// `...+`
    /// Matches as many times as possible
    GREEDY = 16
}

public enum : ubyte
{
    /// Match more than once
    GLOBAL = 2,
    /// ^ & $ match start & end
    MULTILINE = 4,
    /// Case insensitive
    INSENSITIVE = 8,
    /// Ignore whitespace
    EXTENDED = 16,
    /// . matches \r\n\f
    SINGLELINE = 32
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
    /// Characters mapped (like in a character set or literal)
    /// Elements mapped (like in a group or reference)
    uint start;
    /// Minimum times to require fulfillment
    /// eg: `1`
    uint min;
    /// Maximum times to allow fulfillment
    /// eg: `1`
    uint max;

    /++
        Checks if the requirements of this element can be fulfilled in the given text.
        
        Params:
        - `elements`: An array of elements defining the pattern to match.
        - `next`: An unsigned integer representing the next element to check.
        - `table`: A character array used for matching specific characters.
        - `flags`: An unsigned byte containing flags for various matching conditions.
        - `text`: The string in which the pattern is being searched.
        - `idx`: A reference to an unsigned integer indicating the current index in the text.

        Returns:
            A boolean indicating if the requirements of this element can be fulfilled in the given text.

        Remarks:
            This function recursively checks elements against the provided text to determine if the pattern is fulfilled.
            May modify `idx`.

        Example:
            ```d
            Element[] elements = [/*...*/];
            char[] table = "abc";
            uint idx = 0;
            uint next = 1;
            ubyte flags = 0;
            string text = "example text";
            bool result = fulfilled(elements, next, table, flags, text, idx);
            ```
    +/
    pragma(inline, true);
    pure @nogc bool fulfilled(Element[] elements, uint next, char[] table, ubyte flags, string text, ref uint idx)
    {
        foreach (k; 0..(max == 0 ? 1 : max)) 
        {
            if (k != 0)
                idx++;

            if (token != ANCHOR_END && idx >= text.length)
            {
                idx--;
                return k >= min;
            }

            switch (token) 
            {
                case LOOK_AHEAD:
                    uint currIdx = idx - 1;
                    foreach (i; 0..length) 
                    {
                        if (!elements[start + i].fulfilled(elements, next, table, flags, text, idx)) 
                        {
                            if (k >= min)
                                idx = currIdx;

                            return k >= min;
                        }
                    }
                    break;

                case LOOK_BEHIND:
                    return false;

                case CHARACTERS:
                    bool match = false;
                    foreach (i; 0..length) 
                    {
                        if (table[start + i] == text[idx])
                            match = true;
                    }
                    
                    if (((modifiers & EXCLUSIONARY) != 0) ? match : !match) 
                    {
                        if (k >= min)
                            idx--;

                        return k >= min;
                    }
                    break;

                case ANCHOR_START:
                    return idx == 0 || ((flags & MULTILINE) != 0 && (text[idx - 1] == '\r' || text[idx - 1] == '\n' || text[idx - 1] == '\f'));

                case ANCHOR_END:
                    return idx >= text.length || ((flags & MULTILINE) != 0 && (text[idx + 1] == '\r' || text[idx + 1] == '\n' || text[idx + 1] == '\f' || text[idx + 1] == '\0'));

                case GROUP:
                    uint currIdx = idx - 1;
                    foreach (i; 0..length) 
                    {
                        if (!elements[start + i].fulfilled(elements, next, table, flags, text, idx)) 
                        {
                            if (k >= min)
                                idx = currIdx;

                            return k >= min;
                        }
                    }

                    foreach (i; 0..length) 
                    {
                        if (elements[start].min != 0)
                            idx++;
                    }
                    break;

                case ANY:
                    if ((flags & SINGLELINE) == 0 && (text[idx] == '\r' || text[idx] == '\n' || text[idx] == '\f')) 
                    {
                        if (k >= min)
                            idx--;
                        
                        return k >= min;
                    }
                    break;

                case REFERENCE:
                    if (!elements[start].fulfilled(elements, next, table, flags, text, idx)) 
                    {
                        if (k >= min)
                            idx--;
                        
                        return k >= min;
                    }

                    idx += elements[start].min;
                    break;

                case PUSHFW:
                    idx += length;
                    return true;

                case PUSHBW:
                    idx -= length;
                    return true;

                default:
                    return false;
            }
        }
        return true;
    }
}

private template localCache()
{
    char[] table = [ 0 ];
    uint[2][string] lookups;

    /// Pure, must be from a mixin template!
    uint[2] insert(string pattern)
    {
        if (pattern in lookups)
            return lookups[pattern];

        uint cur = cast(uint)table.length;
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
                    pattern ~= table[tup[0]..tup[1]];
                }

                continue;
            }
            else if (i + 1 < pattern.length && pattern[i + 1] == '-')
            {
                // Could hypothetically implement a check for if there is only 1 unexpanded pattern
                // and if so, simply do a lookup for that, but it seems highly inefficient
                if (i + 4 < pattern.length && pattern[i + 3] == '\\')
                {
                    lookups[pattern[i..(i + 4)]] = [cast(uint)table.length - 1, (pattern[i + 3] + 1) - pattern[i]];
                    // Iterate set (a-\z would expand to alpha)
                    foreach (char c; pattern[i]..(pattern[i += 3] + 1))
                        table ~= c;
                }
                else
                {
                    lookups[pattern[i..(i + 3)]] = [cast(uint)table.length - 1, (pattern[i + 2] + 1) - pattern[i]];
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

        return lookups[pattern] = [cur, cast(uint)(table.length - curlen)];
    }

    /// Pure, must be from a mixin template!
    uint[2] insert(char c)
    {
        foreach (uint i; 0..cast(uint)table.length)
        {
            if (table[i] == c)
                return [i, 1];
        }

        table ~= c;
        return [cast(uint)table.length - 1, 1];
    }
}

private alias cache = Cache!();
private template Cache()
{
public:
    mixin localCache;

private:
    static this()
    {
        lookups["\\w"] = insert("a-zA-Z0-9_");
        lookups["\\d"] = insert("0-9");
        lookups["\\s"] = insert(" \t\r\n\f");
        lookups["\\h"] = insert(" \t");
        lookups["\\t"] = insert("\t");
        lookups["\\r"] = insert("\r");
        lookups["\\n"] = insert("\n");
        lookups["\\f"] = insert("\f");
        lookups["\\v"] = insert("\v");
        lookups["\\b"] = insert("\b");
        lookups["\\a"] = insert("\a");
        lookups["\\0"] = insert("\0");
    }
}

pragma(inline, true);
pure @nogc bool mayQuantify(Element element)
{
    return (element.modifiers & QUANTIFIED) == 0;
}

pragma(inline, true);
pure @nogc bool shouldQuantify(Element element)
{
    return element.token != ANCHOR_START && element.token != ANCHOR_END && element.token != PUSHFW && element.token != PUSHBW;
}

pure @nogc string getArgument(string pattern, int start, char opener, char closer)
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

/**
    Builds an array of regex elements based on the provided pattern using a specified cache function.

    This function is realistically pure but cannot be marked as pure due to its invocation of 
    an arbitrary function (`fn`).

    Parameters:
        `fn`: The function used for character mapping.
        `pattern`: The regex pattern to parse.

    Returns:
        An array of `Element` objects built from the given pattern.

    Example Usage:
        ```
        auto elements = "a+b*c?".build!insert();
        ```
*/
// TODO: \b \B \R groups lookahead lookbehind
pragma(inline, true);
private Element[] build(alias fn)(string pattern)
{
    Element[] elements;
    for (int i; i < pattern.length; i++)
    {
        Element element;
        char c = pattern[i];
        switch (c)
        {
            case '+':
                if (!elements[$-1].shouldQuantify)
                    continue;

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
                if (!elements[$-1].shouldQuantify)
                    continue;

                if (!elements[$-1].mayQuantify)
                    continue;

                elements[$-1].min = 0;
                elements[$-1].max = uint.max;
                elements[$-1].modifiers |= QUANTIFIED;
                break;

            case '?':
                if (!elements[$-1].shouldQuantify)
                    continue;

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
                if (!elements[$-1].shouldQuantify)
                    continue;

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
                if (i + 2 < pattern.length && pattern[i..(i + 3)] == "|->")
                {
                    element.token = PUSHFW;
                    element.length = 1;
                    i += 2;
                    break;
                }
                elements[$-1].modifiers |= ALTERNATE;
                break;

            case '.':
                element.token = ANY;
                element.min = 1;
                element.max = 1;
                break;

            case '[':
                if (i + 1 < pattern.length && pattern[i + 1] == '^')
                {
                    element.modifiers |= EXCLUSIONARY;
                    i++;
                }

                element.token = CHARACTERS;
                auto tup = fn(pattern.getArgument(i, '[', ']'));
                element.start = tup[0];
                element.length = tup[1];
                element.min = 1;
                element.max = 1;

                i += pattern.getArgument(i, '[', ']').length + 1;
                break;

            case '^':
                element.token = ANCHOR_START;
                break;

            case '%':
                if (i + 1 < pattern.length && pattern[i + 1].isDigit)
                {
                    uint id = 0;
                    while (i + 1 < pattern.length && pattern[i + 1].isDigit)
                        id = id * 10 + (pattern[++i] - '0');

                    if (id < elements.length)
                    {
                        element.token = REFERENCE;
                        element.length = 1;
                        element.start = id;
                    }
                    break;
                }
                break;

            case '$':
                if (i + 1 < pattern.length && pattern[i + 1].isDigit)
                {
                    uint id = 0;
                    while (i + 1 < pattern.length && pattern[i + 1].isDigit)
                        id = id * 10 + (pattern[++i] - '0');

                    for (uint ii = 0, visits = 0; ii < elements.length; ++ii)
                    {
                        if (elements[ii].token == GROUP && visits++ == id)
                        {
                            element.token = REFERENCE;
                            element.length = 1;
                            element.start = cast(uint)ii;
                            break;
                        }
                    }
                }
                element.token = ANCHOR_END;
                break;

            case '<':
                if (i + 2 < pattern.length && pattern[i + 1] == '-' && pattern[i + 2] == '|')
                {
                    element.token = PUSHBW;
                    element.length = 1;
                    i += 2;
                    break;
                }
                else if (i + 2 < pattern.length && pattern[i + 1] == '-' && pattern[i + 2].isDigit)
                {
                    i++;
                    uint len = 0;
                    while (i + 1 < pattern.length && pattern[i + 1].isDigit)
                        len = len * 10 + (pattern[++i] - '0');

                    element.token = PUSHBW;
                    element.length = len;
                    break;
                }
                break;

            default:
                if (c.isDigit)
                {
                    uint ci = i;
                    uint len = c - '0';
                    while (i + 1 < pattern.length && pattern[i + 1].isDigit)
                        len = len * 10 + (pattern[++i] - '0');
                    
                    if (i + 2 < pattern.length && pattern[(i + 1)..(i + 3)] == "->")
                    {
                        element.token = PUSHFW;
                        element.length = len;
                        i += 2;
                        break;
                    }
                    i = ci;
                }

                element.token = CHARACTERS;
                // Will not be adding support for \gn
                // Expected to use $n
                if (c == '\\' && i + 1 < pattern.length)
                {
                    // Reset (local)
                    if (pattern[i..(i + 2)] == r"\K")
                    {
                        i++;
                        element.token = RESET;
                        if (i + 1 < pattern.length && pattern[i + 1].isDigit)
                        {
                            uint id = 0;
                            while (i + 1 < pattern.length && pattern[i + 1].isDigit)
                                id = id * 10 + (pattern[++i] - '0');

                            for (uint ii = 0, visits = 0; ii < elements.length; ++ii)
                            {
                                if (elements[ii].token == GROUP && visits++ == id)
                                {
                                    element.token = REFERENCE;
                                    element.length = 1;
                                    element.start = cast(uint)ii;
                                    break;
                                }
                            }
                        }
                        break;
                    }
                    // Escaped escape
                    else if (pattern[i..(i + 2)] == r"\\")
                    {
                        element.start = fn(c)[0];
                        element.length = 1;
                        element.min = 1;
                        element.max = 1;
                        i++;
                        break;
                    }
                    else if (pattern[i..(i + 2)] == r"\x" && i + 3 < pattern.length)
                    {
                        string hex = pattern[i + 2 .. i + 4];
                        element.start = fn(cast(char)hex.to!ubyte(16))[0];
                        element.length = 1;
                        element.min = 1;
                        element.max = 1;
                        i += 3;
                        break;
                    }
                    // Any escape
                    else
                    {
                        string arg = pattern[i..(++i + 1)];
                        switch (arg)
                        {
                            case r"\W", r"\D", r"\S", r"\H", r"\V":
                                auto tup = fn(arg.toLower);
                                element.start = tup[0];
                                element.length = tup[1];
                                element.min = 1;
                                element.max = 1;
                                element.modifiers |= EXCLUSIONARY;
                                break;

                            default:
                                auto tup = fn(arg);
                                element.start = tup[0];
                                element.length = tup[1];
                                element.min = 1;
                                element.max = 1;
                        }
                    }
                }
                else
                {
                    element.start = fn(c)[0];
                    element.length = 1;
                    element.min = 1;
                    element.max = 1;
                }
                break;
        }
        if (element.token != BAD)
            elements ~= element;
    }
    return elements;
}

pragma(inline, true);
private static pure @string mmatch(Element[] elements, char[] table, ubyte flags, string text)
{
    string match;
    uint textIndex = 0;
    uint elementIndex = 0;
    
    while (elementIndex < elements.length)
    {
        Element element = elements[elementIndex];
        
        if (element.token != ANCHOR_END && textIndex >= text.length)
            return null;
        
        uint textCopyIndex = textIndex;
        
        if (element.fulfilled(elements, elementIndex + 1, table, flags, text, textIndex))
        {
            uint end = element.min != 0 ? ++textIndex : textCopyIndex;
            match ~= text[textCopyIndex..end];
            elementIndex++;
        }
        else if (element.token == RESET)
        {
            match = null;
        }
        else if ((element.modifiers & ALTERNATE) != 0)
        {
            elementIndex++;
            
            if (element.fulfilled(elements, elementIndex + 1, table, flags, text, textIndex))
            {
                uint end = element.min != 0 ? ++textIndex : textCopyIndex;
                match ~= text[textCopyIndex..end];
                elementIndex++;
            }
        }
        else
        {
            if (!elements[0].fulfilled(elements, elementIndex + 1, table, flags, text, textIndex))
                textIndex++;
            
            match = null;
            elementIndex = 0;
        }
    }
    
    return match;
}

/** Provides interface for compile-time regex.
   
    Not to be confused with `Regex`, which is used for runtime regex generated at runtime.

    Remarks:
        Does not benefit from caching, so use the `Regex` class instead when possible.

    Examples:
        ```d
        regex!(r"\s", GLOBAL).match!("hey, I just met you, and this is crazy but here's my number, so call me, maybe");
        ```
        ```d
        Regex rg = regex!(r"\s", GLOBAL).ctor;
        ```
*/
public template regex(string PATTERN, ubyte FLAGS)
{
public:
    Regex ctor()
    {
        return new Regex(PATTERN, FLAGS);
    }

    string match(string TEXT)()
    {
        mixin localCache;
        lookups["\\w"] = insert("a-zA-Z0-9_");
        lookups["\\d"] = insert("0-9");
        lookups["\\s"] = insert(" \t\r\n\f");
        lookups["\\h"] = insert(" \t");
        lookups["\\t"] = insert("\t");
        lookups["\\r"] = insert("\r");
        lookups["\\n"] = insert("\n");
        lookups["\\f"] = insert("\f");
        lookups["\\v"] = insert("\v");
        lookups["\\b"] = insert("\b");
        lookups["\\a"] = insert("\a");
        lookups["\\0"] = insert("\0");

        foreach (element; PATTERN.build!insert)
            element.writeln;
        return mmatch(PATTERN.build!insert, table, FLAGS, TEXT);
    }
}

/** Provides interface for runtime regex.
   
    Not to be confused with `regex`, which is used for building or executing comptime regex.

    Remarks:
        May be built at compile time with regex!(PATTERN, FLAGS).ctor.
    
    Examples:
        ```
        Regex rg = new Regex(r"[ab]", GLOBAL);
        writeln(rg.match("hey, I just met you, and this is crazy but here's my number, so call me, maybe"));
        ```
*/
public class Regex
{
private:
    Element[] elements;
    ubyte flags;

public:
    
    this(string pattern, ubyte flags)
    {
        this.elements = pattern.build!(cache.insert);
        foreach (element; pattern.build!(cache.insert))
            element.writeln;
        this.flags = flags;
    }

    string match(string text)
    {
        return mmatch(elements, cache.table, flags, text);
    }
}