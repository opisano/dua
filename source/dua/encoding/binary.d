module dua.encoding.binary;

import dua.except;
import dua.node;
import std.algorithm.mutation: reverse;
import std.bitmanip;
import std.datetime;
import std.exception;
import std.sumtype;
import std.traits;
import std.uuid;

@safe:

alias bstring = immutable(ubyte)[];

version (unittest)
{
    import std.algorithm.comparison: equal;
}

/** 
 * Encodes in binary format.
 */
struct BinaryEncoder 
{
    /** 
     * Encode a boolean value
     * 
     * A Boolean value shall be encoded as a single byte where a value of 0 (zero) is false and any non-zero 
     * value is true. 
     *
     * Encoders shall use the value of 1 to indicate a true value; however, decoders shall treat any non-zero 
     * value as true. 
     * 
     * This function writes the value at the beginning of provided buffer then returns the remaining window 
     * of the buffer. 
     * 
     * Params: 
     *     T = The type to encode
     *     buffer = Buffer where to encode the value
     *     value = Value to encode 
     * 
     * Returns:
     *     The remaining part of the buffer after the written value
     *
     * Throws: 
     *     DuaBadEncodingException if there is not enough space left in the buffer.
     */
    ubyte[] encode(T)(return scope ubyte[] buffer, T value) scope 
            if (is(T == bool))
    {
        enforce!DuaBadEncodingException(buffer.length > 0, "No space left to encode value");

        buffer[0] = value ? 1 : 0;
        return buffer[1 .. $];
    }

    unittest
    {
        // check we can encode a 16 bit integer in a 8 byte buffer
        ubyte[] buffer = [0, 0, 0, 0, 0, 0, 0, 0];
        BinaryEncoder be;
        ubyte[] remaining = be.encode!bool(buffer, true);

        assert (buffer.equal([1, 0, 0, 0, 0, 0, 0, 0]));
        assert (remaining.equal([0, 0, 0, 0, 0, 0, 0]));

        remaining = be.encode!bool(remaining, false);
        assert (buffer.equal([1, 0, 0, 0, 0, 0, 0, 0]));
        assert (remaining.equal([0, 0, 0, 0, 0, 0]));

        // check an error is thrown if there is no space
        remaining = [];
        assertThrown!DuaBadEncodingException(be.encode!bool(remaining, true));
    }


    /** 
     * Encode an integer or a floating point value
     * 
     * All integer types shall be encoded as little-endian values where the least significant byte appears first in 
     * the stream.
     *
     * This function writes the value at the beginning of provided buffer then returns the remaining window 
     * of the buffer. 
     * 
     * Params: 
     *     T = The type to encode
     *     buffer = Buffer where to encode the value
     *     value = Value to encode 
     *
     * Returns:
     *     The remaining part of the buffer after the written value
     *
     * Throws: 
     *     DuaBadEncodingException if there is not enough space left in the buffer.
     */
    ubyte[] encode(T)(return scope ubyte[] buffer, T value) scope 
            if (isIntegral!T || isFloatingPoint!T)
    {
        enforce!DuaBadEncodingException(buffer.length >= T.sizeof, "No space left to encode value");

        std.bitmanip.write!(T, Endian.littleEndian)(buffer, value, 0);
        return buffer[T.sizeof .. $];
    }

    unittest 
    {
        // check we can encode a 16 bit integer in a 8 byte buffer
        ubyte[] buffer = [0, 0, 0, 0, 0, 0, 0, 0];
        BinaryEncoder be;
        ubyte[] remaining = be.encode!ushort(buffer, 0xCAFE);

        assert (remaining.equal([0, 0, 0, 0, 0, 0]));
        assert (buffer.equal([0xFE, 0xCA, 0, 0, 0, 0, 0, 0]));

        ubyte[] left = be.encode!float(remaining, -6.5f);
        assert (remaining.equal([0, 0, 0xD0, 0xC0, 0, 0]));
        assert (left.equal([0, 0]));

        // check an error is thrown if we try to encode a 64 bit value in the remaining bytes 
        assertThrown!DuaBadEncodingException(be.encode!ulong(left, 0x123412341234124));
    }


    /** 
     * Encode a string value
     *
     * All String values are encoded as a sequence of UTF-8 characters preceded by the length in bytes.
     * 
     * The length in bytes is encoded as Int32. A value of −1 is used to indicate a ‘null’ string. 
     * 
     * Params: 
     *     T = The type to encode
     *     buffer = Buffer where to encode the value
     *     value = Value to encode 
     *
     * Returns:
     *     The remaining part of the buffer after the written value
     *
     * Throws: 
     *     DuaBadEncodingException if there is not enough space left in the buffer.
     */
    ubyte[] encode(T)(return scope ubyte[] buffer, scope T value) scope 
            if (is(T == string) || is(T == bstring))
    {
        enforce!DuaBadEncodingException((value is null && buffer.length >= int.sizeof) 
                                        || ((buffer.length >= value.length + int.sizeof)
                                            && (value.length <= int.max)),
                                        "Not enough space");

        if (value is null)
        {
            return encode!int(buffer, -1);
        }
        else 
        {
            int len = cast(int) value.length;
            buffer = encode!int(buffer, len);
            buffer[0 .. len] = cast(immutable(ubyte)[])value[0 .. len];
            return buffer[len .. $];
        }
    }

    unittest 
    {
        // Check non-null string
        ubyte[] buffer = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        BinaryEncoder be;
        ubyte[] remaining = be.encode!string(buffer, "水Boy");

        assert (buffer.equal([0x06, 0, 0, 0, 0xE6, 0xB0, 0xB4, 0x42, 0x6F, 0x79, 0, 0]));
        assert (remaining.equal([0, 0]));

        // check null string
        buffer[] = 0;
        remaining = be.encode!string(buffer, null);
        assert (buffer.equal([0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0]));

        // check string length 
        assertThrown!DuaBadEncodingException(be.encode!string(buffer, "This is a very long string for such a buffer"));
    }


    /** 
     * Encode a SysTime value
     *
     * A DateTime value shall be encoded as a 64-bit signed integer which represents the number of 100 nanosecond 
     * intervals since January 1, 1601 (UTC).  
     * 
     * Params: 
     *     T = The type to encode
     *     buffer = Buffer where to encode the value
     *     value = Value to encode 
     *
     * Returns:
     *     The remaining part of the buffer after the written value
     *
     * Throws: 
     *     DuaBadEncodingException if there is not enough space left in the buffer.
     */
    ubyte[] encode(T)(return scope ubyte[] buffer, T value) scope 
            if (is(T == SysTime))
    {
        immutable limitLow = SysTime(DateTime(1601, 1, 1, 0, 0, 0), UTC());
        immutable limitHigh = SysTime(DateTime(9999, 12, 31, 11, 59, 59), UTC());

        long encodedValue = 0;

        if (value > limitLow && value < limitHigh)
        {
            Duration dur = value - limitLow;
            encodedValue = dur.total!"hnsecs";
        }

        return encode!long(buffer, encodedValue);
    }

    unittest 
    {
        ubyte[] buffer = [0, 0, 0, 0, 0, 0, 0, 0];
        BinaryEncoder be;
        auto time1 = SysTime(DateTime(1601, 1, 1, 1, 0, 0), UTC());
        ubyte[] remaining = be.encode!SysTime(buffer, time1);

        assert (buffer.equal([0, 0x68, 0xc4, 0x61, 0x08, 0, 0, 0]));
        assert (remaining.length == 0);
    }

    /** 
     * Encode a GUID value
     *
     * A DateTime value shall be encoded as a 64-bit signed integer which represents the number of 100 nanosecond 
     * intervals since January 1, 1601 (UTC).  
     * 
     * Params: 
     *     T = The type to encode
     *     buffer = Buffer where to encode the value
     *     value = Value to encode 
     *
     * Returns:
     *     The remaining part of the buffer after the written value
     *
     * Throws: 
     *     DuaBadEncodingException if there is not enough space left in the buffer.
     */
    ubyte[] encode(T)(return scope ubyte[] buffer, T value) scope 
            if (is(T == UUID))
    {
        enforce!DuaBadEncodingException(buffer.length >= 16, "No space left to encode value");

        buffer[0 .. 16] = value.data[0 .. 16];

        version (LittleEndian)
        {
            // std.uuid uses big endian, convert to little endian
            buffer[0 .. 4].reverse();
            buffer[4 .. 6].reverse();
            buffer[6 .. 8].reverse();
        }

        return buffer[16..$];
    }

    unittest 
    {
        // Check non-null string
        ubyte[] buffer = [0, 0, 0, 0, 0, 0, 0, 0, 
                          0, 0, 0, 0, 0, 0, 0, 0];

        auto value = UUID("72962B91-FA75-4AE6-8D28-B404DC7DAF63");
        BinaryEncoder be;
        ubyte[] remaining = be.encode!UUID(buffer, value);

        assert (buffer.equal([0x91, 0x2B, 0x96, 0x72, 0x75, 0xFA, 0xE6, 0x4A,
                              0x8D, 0x28, 0xB4, 0x04, 0xDC, 0x7D, 0xAF, 0x63]));
    }


    ubyte[] encode(T)(return scope ubyte[] buffer, T value) scope 
            if (is(T == NodeId))
    {
        // calculate space needed to encode value
        size_t neededSpace = 1 + 2 +
            value.identifier.match!(
                (uint v) => 4,
                (string v) => 4 + v.length,
                (UUID v) => 16,
                (bstring v) => 4 + v.length
            );
        
        enforce!DuaBadEncodingException(buffer.length >= neededSpace, "No space left to encode value");

        // first byte is encoding byte
        buffer[0] = cast(ubyte) value.identifier.match!(
            (uint v) => 0x02,
            (string v) => 0x03,
            (UUID v) => 0x04,
            (bstring v) => 0x05
        );

        // next two bytes are namespace index 
        std.bitmanip.write!(ushort, Endian.littleEndian)(buffer, value.namespaceIndex, 1);

        buffer = buffer[3 .. $];

        // then encode indentifier
        value.identifier.match!(
            (uint v) 
            {
                buffer = encode!uint(buffer, v);
            },
            (string v)
            {
                buffer = encode!string(buffer, v);
            },
            (UUID v)
            {
                buffer = encode!UUID(buffer, v);
            },
            (bstring v)
            {
                buffer = encode!bstring(buffer, v);
            },
        );

        return buffer;
    }

    unittest 
    {
        ubyte[] buffer = [0, 0, 0, 0, 0, 0, 0, 0, 
                          0, 0, 0, 0, 0, 0, 0, 0];
        
        // check string NodeId
        auto n = NodeId(2, "Hot水");
        BinaryEncoder be;
        ubyte[] remaining = be.encode!NodeId(buffer, n);

        assert (remaining.equal([0, 0, 0]));
        assert (buffer.equal([0x03, 0x02, 0x00, 0x06, 0x00, 0x00, 0x00, 0x48,
                              0x6F, 0x74, 0xE6, 0xB0, 0xB4, 0x00, 0x00, 0x00]));

    }
}


