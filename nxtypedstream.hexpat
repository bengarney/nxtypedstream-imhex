// imhex pattern implementation for reading nxtypedstream data as found
// in some Messages.app chat records and other strange places in macOS.
//
// Not heavily tested, but works pretty well. Does a neat thing with imhex
// sections to store data for backreferences, perhaps the most interesting
// thing here.
//
// Thanks to dgelessus and the python-typedstream package they released!
//
// Feb 2023 - Ben Garney <ben@theengine.co>

#include <std/io.pat>
#include <std/mem.pat>
#include <std/sys.pat>
#include <std/string.pat>
#include <std/mem.pat>

std::mem::Section strings = std::mem::create_section("String Cache");

enum StreamVersion : s8
{
    OLD_NEXTSTEP = 3,
    CURRENT = 4
};

enum TagType : s8
{
    TAG_INTEGER_2 = 0x81,      // Indicates an integer value, stored in 2 bytes.
    TAG_INTEGER_4 = 0x82,      // Indicates an integer value, stored in 4 bytes.
    TAG_FLOATING_POINT = 0x83, // Indicates a floating-point value, stored in 4 or 8 bytes (depending on whether it is a float or a double).
    TAG_NEW = 0x84,            // Indicates the start of a string value or an object that is stored literally and not as a backreference.
    TAG_NIL = 0x85,            // Indicates a nil value. Used for strings (unshared and shared), classes, and objects.
    TAG_END_OF_OBJECT = 0x86,  // Indicates the end of an object.

    //    FIRST_TAG = 0x81,
    //    LAST_TAG = 0x91,
};

struct StrCacheEntry
{
    u8 length;
    char value[127];
};

u32 cachedStringsNextId @0x0 in strings;
StrCacheEntry cachedStrings[16] @0x4 in strings;

fn cacheEntryToString(u32 idx)
{
    str x = "";
    u32 i = 0;

    for (i = 0, i < cachedStrings[idx].length && i < 126, i = i + 1)
        x = x + std::format("{}", cachedStrings[idx].value[i]);

    return x;
};

fn strlen(str s)
{
    u32 i = 0;
    u32 sLen = 0;

    for (i = 0, i < std::string::length(s) && i < 126, i = i + 1)
    {
        if (std::string::at(s, i) == 0)
            break;
        sLen = i;
    }
    return sLen + 1;
};

fn strcmp(str a, str b)
{
    u16 aLen = strlen(a);
    u16 bLen = strlen(b);

    if (aLen != bLen)
        return false;

    u32 i = 0;
    for (i = 0, i < aLen && i < 126, i = i + 1)
        if (std::string::at(a, i) != std::string::at(b, i))
            return false;
    return true;
};

fn storeCachedString(str s)
{
    u32 i = 0;
    u32 sLen = strlen(s);

    // std::print("Checking for {}, got len = {}", s, sLen);

    bool found = false;

    for (i = 0, i < cachedStringsNextId, i = i + 1)
    {
        str e = cacheEntryToString(i);

        // std::print("    '{}' VS '{}'", s, e);

        if (!strcmp(e, s))
            continue;

        found = true;
        break;
    }

    if (!found)
    {
        u32 idx = cachedStringsNextId;

        for (i = 0, i < sLen && i < 125, i = i + 1)
        {
            char c = std::string::at(s, i);
            if (c == 0)
                break;
            cachedStrings[idx].value[i] = c;
        }

        cachedStrings[idx].length = i;

        std::print("Storing cached string '{}' #{} len={}", s, idx, cachedStrings[idx].length);
        // std::print("SET {}", cacheEntryToString(idx));

        cachedStringsNextId = cachedStringsNextId + 1;
    }
    else
    {
        // std::print("HAD IT");
    }
};

struct String
{
    char length;
    if (length >= 0)
        char s[length];
    else
        char s[1] [[no_unique_address]];
} [[format("formatString")]];

fn formatString(String s)
{
    return s.s;
};

fn isInTagRange(TagType v)
{
    return (v >= 0x81 && v <= 0x91);
};

struct Integer
{

    TagType marker;

    if (!isInTagRange(marker))
    {
        $ = $ - 1;
        s8 value;
    }
    else if (marker == TagType::TAG_INTEGER_2)
        s16 value;
    else if (marker == TagType::TAG_INTEGER_4)
        s32 value;
    else
    {
        std::print("Invalid Integer type {} @ {}", marker, $);
    }
} [[format("formatInteger")]];

fn formatInteger(Integer x)
{
    return std::format("{}", x.value);
};

struct SharedStringDummy
{
    char s[1] [[no_unique_address]];
};

struct SharedStringIndexResolver
{
    s8 index; // [[no_unique_address]];
};

struct SharedString
{
    TagType marker;

    if (marker == TagType::TAG_NEW)
    {
        String value [[transform("realStringToValue"), format("realStringToValue")]];
    }
    else if (marker == TagType::TAG_NIL)
    {
        SharedStringDummy value [[no_unique_address, transform("dummyStringToValue"), format("dummyStringToValue")]];
    }
    else
    {
        $ = $ - 1;
        SharedStringIndexResolver value [[transform("indexToString"), format("indexToString")]];
    }

} [[format("sharedStringToString")]];

fn sharedStringToString(SharedString v)
{
    return v.value;
};

fn realStringToValue(String v)
{
    return v.s;
};

fn dummyStringToValue(SharedStringDummy ssd)
{
    return "";
};

fn indexToString(SharedStringIndexResolver v)
{
    s8 idx = char(char(v.index) - char(0x92));
    if (idx < 0 || idx >= cachedStringsNextId)
    {
        std::print("OOB shared id {}, {} >= {}", v.index, idx, cachedStringsNextId);
        return "[invalid id]";
    }
    std::print("idx={}", idx);
    // std::print("idx={} str={}", idx, cachedStrings[idx].value);
    return cacheEntryToString(idx);
};

fn formatSharedString(SharedString s)
{
    return s.value + "str";
};

struct Class
{
    TagType marker;

    if (marker == TagType::TAG_NIL)
        break;
    else if (marker == TagType::TAG_NEW)
    {
        SharedString name;
        // storeCachedString(name.value);
        Integer version;
    }
    else
    {
        $ = $ - 1;
        s8 referenceId;
        break;
    }

} [[format("formatClass")]];

fn formatClass(Class c)
{
    if (c.marker == TagType::TAG_NIL)
        return "[nil]";
    else if (c.marker == TagType::TAG_NEW)
        return c.name.value;
    else
        return std::format("[ref #{}]", c.referenceId);
};

using Value;
using ValueList;
using ValueWrapper;

struct Object
{
    TagType marker;

    if (marker == TagType::TAG_NIL)
        break;

    Class clazz[4];

    Value values[24][[inline]];
};

struct Value
{
    char peek [[no_unique_address, hidden]];
    if (peek == 0x86)
    {
        char endOfObject;
        break; // end of object
    }
    else
    {
        SharedString encoding;

        storeCachedString(encoding.value);

        if (strcmp(encoding.value, "@"))
        {
            // Begin object
            Object o;
        }
        else if (strcmp(encoding.value, "+"))
        {
            String s;
        }
        else if (strcmp(encoding.value, "*"))
        {
            SharedString s;
        }
        else if (strcmp(encoding.value, "iI"))
        {
            Integer i;
            Integer I;
        }
        else
        {
            std::print("Unknown value encoding '{}'", encoding.value);
        }
    }
};

struct ValueWrapper
{
    TagType marker;

    if (marker == TagType::TAG_NIL || marker == TagType::TAG_END_OF_OBJECT)
    {
        break;
    }
    else if (marker == TagType::TAG_NEW)
    {
        $ = $ + 1;
        Value v;
    }
    else
    {
        $ = $ - 1;
        Value v;
    }
}[[inline]];

struct Header
{
    u8 streamVersion;
    String id;
    Integer systemVersion;
};

struct TypedStream
{
    Header header;
};

Header header @0x0;
Value data[16] @0x10;

