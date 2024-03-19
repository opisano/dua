module dua.encoding.binary;

import dua.except;
import dua.node;
import dua.diagnosticinfo;
import dua.statuscode;
import std.algorithm.mutation: reverse;
import std.bitmanip;
import std.datetime;
import std.exception;
import std.sumtype;
import std.traits;
import std.typecons;
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
    static ubyte[] encode(T)(return scope ubyte[] buffer, T value) 
            if (is(T == bool))
    {
        enforce!DuaBadEncodingException(buffer.length > 0, "No space left to encode value");

        buffer[0] = value ? 1 : 0;
        return buffer[1 .. $];
    }

    unittest
    {
        // check we can encode a 16 bit integer in a 8 byte buffer
        ubyte[8] buffer;
        BinaryEncoder be;
        ubyte[] remaining = be.encode!bool(buffer, true);

        assert (buffer[].equal([1, 0, 0, 0, 0, 0, 0, 0]));
        assert (remaining.length == 7);

        remaining = be.encode!bool(remaining, false);
        assert (buffer[].equal([1, 0, 0, 0, 0, 0, 0, 0]));
        assert (remaining.length == 6);

        // check an error is thrown if there is no space
        remaining = [];
        assertThrown!DuaBadEncodingException(be.encode!bool(remaining, true));
    }


    /** 
     * Returns the byte count needed to encode value
     * 
     * Params: 
     *     value = value to encode
     *
     * Returns: 
     *     The byte count.
     */
    static size_t encodeSize(T)(T value) if (is(T == bool))
    {
        return 1;
    }

    unittest 
    {
        assert (BinaryEncoder.encodeSize(true) == 1);
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
    static ubyte[] encode(T)(return scope ubyte[] buffer, T value)
            if (isIntegral!T || isFloatingPoint!T)
    {
        enforce!DuaBadEncodingException(buffer.length >= T.sizeof, "No space left to encode value");

        std.bitmanip.write!(T, Endian.littleEndian)(buffer, value, 0);
        return buffer[T.sizeof .. $];
    }

    unittest 
    {
        // check we can encode a 16 bit integer in a 8 byte buffer
        ubyte[8] buffer;
        BinaryEncoder be;
        ubyte[] remaining = be.encode!ushort(buffer, 0xCAFE);

        assert (remaining.length == 6);
        assert (buffer[].equal([0xFE, 0xCA, 0, 0, 0, 0, 0, 0]));

        ubyte[] left = be.encode!float(remaining, -6.5f);
        assert (remaining.equal([0, 0, 0xD0, 0xC0, 0, 0]));
        assert (left.length == 2);

        // check an error is thrown if we try to encode a 64 bit value in the remaining bytes 
        assertThrown!DuaBadEncodingException(be.encode!ulong(left, 0x123412341234124));
    }


    /** 
     * Returns the byte count needed to encode value
     * 
     * Params: 
     *     value = value to encode
     *
     * Returns: 
     *     The byte count.
     */
    static size_t encodeSize(T)(T value) if (isIntegral!T || isFloatingPoint!T)
    {
        return T.sizeof;
    }

    unittest
    {
        assert (BinaryEncoder.encodeSize!ushort(42) == 2);
        assert (BinaryEncoder.encodeSize(42) == 4);
        assert (BinaryEncoder.encodeSize(42.0f) == 4);
        assert (BinaryEncoder.encodeSize(42.0) == 8);
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
    static ubyte[] encode(T)(return scope ubyte[] buffer, scope T value)
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
        ubyte[12] buffer;
        BinaryEncoder be;
        ubyte[] remaining = be.encode!string(buffer, "水Boy");

        assert (buffer[].equal([0x06, 0, 0, 0, 0xE6, 0xB0, 0xB4, 0x42, 0x6F, 0x79, 0, 0]));
        assert (remaining.length == 2);

        // check null string
        buffer[] = 0;
        remaining = be.encode!string(buffer, null);
        assert (buffer[].equal([0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0]));
        assert (remaining.length == 8);

        // check string length 
        assertThrown!DuaBadEncodingException(be.encode!string(buffer, "This is a very long string for such a buffer"));
    }


    /** 
     * Returns the byte count needed to encode value
     * 
     * Params: 
     *     value = value to encode
     *
     * Returns: 
     *     The byte count.
     */
    static size_t encodeSize(T)(T value) if (is(T == string) || is(T == bstring))
    {
        size_t size = int.sizeof;

        if (value !is null)
        {
            size += value.length;
        }

        return size;
    }

    unittest 
    {
        assert (BinaryEncoder.encodeSize("水Boy") == 10);
        assert (BinaryEncoder.encodeSize!string(null) == 4);
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
        static immutable minimumDate = SysTime(DateTime(1601, 1, 1, 0, 0, 0), UTC());
        static immutable maximumDate = SysTime(DateTime(9999, 12, 31, 11, 59, 59), UTC());

        long encodedValue = 0;

        if (value > minimumDate && value < maximumDate)
        {
            Duration dur = value - minimumDate;
            encodedValue = dur.total!"hnsecs";
        }

        return encode!long(buffer, encodedValue);
    }

    unittest 
    {
        ubyte[8] buffer;
        BinaryEncoder be;
        auto time1 = SysTime(DateTime(1601, 1, 1, 1, 0, 0), UTC());
        ubyte[] remaining = be.encode!SysTime(buffer, time1);

        assert (buffer[].equal([0, 0x68, 0xc4, 0x61, 0x08, 0, 0, 0]));
        assert (remaining.length == 0);
    }


    /** 
     * Returns the byte count needed to encode value
     * 
     * Params: 
     *     value = value to encode
     *
     * Returns: 
     *     The byte count.
     */
    static size_t encodeSize(T)(T value) if (is(T == SysTime))
    {
        return ulong.sizeof;
    }

    unittest 
    {
        auto time1 = SysTime(DateTime(1601, 1, 1, 1, 0, 0), UTC());
        assert (BinaryEncoder.encodeSize(time1) == ulong.sizeof);
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
        ubyte[16] buffer;

        auto value = UUID("72962B91-FA75-4AE6-8D28-B404DC7DAF63");
        BinaryEncoder be;
        be.encode!UUID(buffer, value);

        assert (buffer[].equal([0x91, 0x2B, 0x96, 0x72, 0x75, 0xFA, 0xE6, 0x4A,
                                0x8D, 0x28, 0xB4, 0x04, 0xDC, 0x7D, 0xAF, 0x63]));
    }


    /** 
     * Returns the byte count needed to encode value
     * 
     * Params: 
     *     value = value to encode
     *
     * Returns: 
     *     The byte count.
     */
    static size_t encodeSize(T)(T value) if (is(T == UUID))
    {
        return value.data.length;
    }

    unittest 
    {
        UUID uuid;
        assert (BinaryEncoder.encodeSize(uuid) == 16);
    }

    /** 
     * Encode a NodeId value
     *
     * the first byte of the encoded form indicates the format of the rest of the encoded NodeId.
     * 
     * Params: 
     *     T = The type to encode
     *     buffer = Buffer where to encode the value
     *     value = Value to encode 
     *     nsUri = The NodeId is followed by a namespaceUri in the stream (when encoding an ExpandedNodeId)
     *     serverIndex = The NodeId is followed by a serverIndex in the stream (when encoding an ExpandedNodeId)
     *
     * Returns:
     *     The remaining part of the buffer after the written value
     *
     * Throws: 
     *     DuaBadEncodingException if there is not enough space left in the buffer.
     */
    ubyte[] encode(T)(return scope ubyte[] buffer, T value, 
            Flag!"namespaceUri" nsUri = No.namespaceUri, 
            Flag!"serverIndex" serverIndex = No.serverIndex ) scope if (is(T == NodeId))
    {
        ubyte encodingByte = nsUri ? 0x80 : 0x00;
        encodingByte |= serverIndex ? 0x40 : 0x00;

        return value.identifier.match!(
            (uint v)
            {
                if (value.namespaceIndex == 0 && v <= ubyte.max)
                {
                    size_t neededSpace = 2;
                    enforce!DuaBadEncodingException(buffer.length >= neededSpace, "No space left to encode value");
                    buffer[0] = encodingByte | 0;
                    buffer[1] = cast(ubyte) v;
                    return buffer[neededSpace .. $];
                }
                else if (value.namespaceIndex <= ubyte.max && v <= ushort.max)
                {
                    size_t neededSpace = 4;
                    enforce!DuaBadEncodingException(buffer.length >= neededSpace, "No space left to encode value");
                    buffer[0] = encodingByte | 1;
                    buffer[1] = cast(ubyte) value.namespaceIndex;
                    std.bitmanip.write!(ushort, Endian.littleEndian)(buffer, cast(ushort)v, 2);
                    return buffer[neededSpace .. $];
                }
                else 
                {
                    size_t neededSpace = 7;
                    enforce!DuaBadEncodingException(buffer.length >= neededSpace, "No space left to encode value");
                    buffer[0] = encodingByte | 2;
                    std.bitmanip.write!(ushort, Endian.littleEndian)(buffer, value.namespaceIndex, 1);
                    std.bitmanip.write!(uint, Endian.littleEndian)(buffer, v, 3);
                    return buffer[neededSpace .. $];
                }
            },
            (string v) 
            {
                size_t neededSpace = 1         // encoding byte
                                   + 2         // namespace index
                                   + 4         // string length
                                   + (v !is null ? v.length : 0);
                enforce!DuaBadEncodingException(buffer.length >= neededSpace, "No space left to encode value");
                buffer[0] = encodingByte | 3;
                std.bitmanip.write!(ushort, Endian.littleEndian)(buffer, value.namespaceIndex, 1);
                buffer = buffer[3 .. $];
                return encode!string(buffer, v);
            },
            (UUID v)
            {
                size_t neededSpace =  1        // encoding byte
                                   +  2        // namespace index 
                                   + 16;       // guid value
                enforce!DuaBadEncodingException(buffer.length >= neededSpace, "No space left to encode value");
                buffer[0] = encodingByte | 4;
                std.bitmanip.write!(ushort, Endian.littleEndian)(buffer, value.namespaceIndex, 1);
                buffer = buffer[3 .. $];
                return encode!UUID(buffer, v);
            },
            (bstring v)
            {
                size_t neededSpace = 1         // encoding byte
                                   + 2         // namespace index
                                   + 4         // string length
                                   + v.length;
                enforce!DuaBadEncodingException(buffer.length >= neededSpace, "No space left to encode value");
                buffer[0] = encodingByte | 5;
                std.bitmanip.write!(ushort, Endian.littleEndian)(buffer, value.namespaceIndex, 1);
                buffer = buffer[3 .. $];
                return encode!bstring(buffer, v);
            }
        );
    }

    unittest 
    {
        // check with 2 byte numeric
        {
            ubyte[4] buffer;
            
            auto n = NodeId(0, 42);
            BinaryEncoder be;
            ubyte[] remaining = be.encode!NodeId(buffer, n);

            assert (remaining.length == 2);
            assert (buffer[].equal([0, 42, 0, 0]));
        }

        // check with 4 byte numeric
        {
            ubyte[5] buffer;
            
            auto n = NodeId(5, 1_025);
            BinaryEncoder be;
            ubyte[] remaining = be.encode!NodeId(buffer, n);

            assert (remaining.length == 1);
            assert (buffer[].equal([1, 5, 0x01, 0x04, 0]));
        }

        // check with numeric 
        {
            ubyte[8] buffer;
            
            auto n = NodeId(300, 500_000);
            BinaryEncoder be;
            ubyte[] remaining = be.encode!NodeId(buffer, n);

            assert (remaining.length == 1);
            assert (buffer[].equal([2, 0x2C, 0x01, 0x20, 0xA1, 0x07, 0x00, 0x00]));
        }

        // Check with string node id
        {
            ubyte[16] buffer;
            
            auto n = NodeId(2, "Hot水");
            BinaryEncoder be;
            ubyte[] remaining = be.encode!NodeId(buffer, n);

            assert (remaining.length == 3);
            assert (buffer[].equal([0x03, 0x02, 0x00, 0x06, 0x00, 0x00, 0x00, 0x48,
                                    0x6F, 0x74, 0xE6, 0xB0, 0xB4, 0x00, 0x00, 0x00]));
        }

        // Check with GUID node id 
        {
            ubyte[32] buffer;

            auto n = NodeId(3, UUID("72962B91-FA75-4AE6-8D28-B404DC7DAF63"));
            BinaryEncoder be;
            ubyte[] remaining = be.encode!NodeId(buffer, n);

            assert (remaining.length == 13);
            assert (buffer[].equal([0x04, 0x03, 0x00, 0x91, 0x2B, 0x96, 0x72, 0x75, 
                                    0xFA, 0xE6, 0x4A, 0x8D, 0x28, 0xB4, 0x04, 0xDC, 
                                    0x7D, 0xAF, 0x63, 0x00, 0x00, 0x00, 0x00, 0x00,
                                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]));

        }

        // Check with binary string 
        ubyte[16] buffer;

        bstring v = [0x01, 0x02, 0x03, 0x04];
        auto n = NodeId(4, v);
        BinaryEncoder be;
        ubyte[] remaining = be.encode!NodeId(buffer, n);

        assert (buffer[].equal([0x05, 0x04, 0x00, 0x04, 0x00, 0x00, 0x00, 0x01,
                                0x02, 0x03, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00]));

        assert (remaining.length == 5);
    }

        /** 
     * Returns the byte count needed to encode value
     * 
     * Params: 
     *     value = value to encode
     *
     * Returns: 
     *     The byte count.
     */
    static size_t encodeSize(T)(T value) if (is(T == NodeId))
    {
        return value.identifier.match!(
            (uint v) 
            {
                if (value.namespaceIndex == 0 && v <= ubyte.max)
                {
                    return 2;
                }
                else if (value.namespaceIndex <= ubyte.max && v <= ushort.max)
                {
                    return 4;
                }
                else
                {
                    return 7;
                }
            },
            (string v)
            {
                size_t neededSpace = 1         // encoding byte
                                   + 2         // namespace index
                                   + 4         // string length
                                   + (v !is null ? v.length : 0);
                return neededSpace;
            },
            (UUID v)
            {
                size_t neededSpace =  1        // encoding byte
                                   +  2        // namespace index 
                                   + 16;       // guid value
                return neededSpace;
            },
            (bstring v)
            {
                size_t neededSpace = 1         // encoding byte
                                   + 2         // namespace index
                                   + 4         // string length
                                   + v.length;
                return neededSpace;
            }
        );
    }

    unittest 
    {
        // test with small integers
        {
            auto n = NodeId(0, 10);
            assert (BinaryEncoder.encodeSize(n) == 2);
        }

        // test with medium integers
        {
            auto n = NodeId(10, 4_096);
            assert (BinaryEncoder.encodeSize(n) == 4);
        }

        // test with large integers 
        {
            auto n = NodeId(300, 100_000);
            assert (BinaryEncoder.encodeSize(n) == 7);
        }

        // test with strings 
        {
            auto n = NodeId(2, "Hot水");
            assert (BinaryEncoder.encodeSize(n) == 13);
        }

        // test with UUID
        {
            auto n = NodeId(3, UUID("72962B91-FA75-4AE6-8D28-B404DC7DAF63"));
            assert (BinaryEncoder.encodeSize(n) == 19);
        }

        // test with bstring 
        {
            bstring v = [0x01, 0x02, 0x03, 0x04];
            auto n = NodeId(4, v);
            assert (BinaryEncoder.encodeSize(n) == 11);
        }
    }


    /** 
     * Encode an ExpandedNodeId value
     *
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
            if (is(T == ExpandedNodeId))
    {
        Flag!"namespaceUri" nsUri = No.namespaceUri;        
        Flag!"serverIndex" serverIndex = No.serverIndex;

        size_t neededSpace;

        /*
          If the NamespaceUri is present, then the encoder shall encode the NamespaceIndex as 0 in the stream when the
          NodeId portion is encoded. The unused NamespaceIndex is included in the stream for consistency. 
        */
        if (value.namespaceUri !is null && value.namespaceUri.length > 0)
        {
            value.nodeId.namespaceIndex = 0;
            nsUri = Yes.namespaceUri;
            neededSpace += int.sizeof + value.namespaceUri.length;
        }

        // The ServerIndex is omitted if it is equal to zero.
        if (value.serverIndex > 0)
        {
            serverIndex = Yes.serverIndex;
            neededSpace += int.sizeof;
        }

        // The ExpandedNodeId is encoded by first encoding a NodeId
        buffer = encode!NodeId(buffer, value.nodeId, nsUri, serverIndex);

        enforce!DuaBadEncodingException(buffer.length >= neededSpace, "No space left to encode value");

        if (nsUri)
            buffer = encode!string(buffer, value.namespaceUri);

        if (serverIndex)
            buffer = encode!uint(buffer, value.serverIndex);

        return buffer;
    }

    unittest 
    {
        // Check without neither nsUri nor serverIndex
        {
            auto en = ExpandedNodeId(NodeId(5, 1_025), null, 0);

            ubyte[5] buffer;
            
            BinaryEncoder be;
            ubyte[] remaining = be.encode!ExpandedNodeId(buffer, en);

            assert (remaining.length == 1);
            assert (buffer[].equal([1, 5, 0x01, 0x04, 0]));
        }

        // Check with a namespace Uri 
        {
            auto en = ExpandedNodeId(NodeId(5, 1_025), "http://tartiflette.org/", 0);

            ubyte[32] buffer;
            
            BinaryEncoder be;
            ubyte[] remaining = be.encode!ExpandedNodeId(buffer, en);

            assert (remaining.length == 1);
            assert (buffer[].equal([0x81, 0, 0x01, 0x04, 0x17, 0, 0, 0, 0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x74, 
                                    0x61, 0x72, 0x74, 0x69, 0x66, 0x6c, 0x65, 0x74, 0x74, 0x65, 0x2e, 0x6f, 0x72, 0x67, 
                                    0x2f, 0]));
        }

        // Check with a server index
        {
            auto en = ExpandedNodeId(NodeId(5, 1_025), null, 42);

            ubyte[8] buffer;
            
            BinaryEncoder be;
            ubyte[] remaining = be.encode!ExpandedNodeId(buffer, en);

            assert (remaining.length == 0);
            assert (buffer[].equal([0x41, 5, 0x01, 0x04, 0x2A, 0, 0, 0]));
        }

        // check with a namespace uri and a server index 
                // Check with a namespace Uri 
        {
            auto en = ExpandedNodeId(NodeId(5, 1_025), "http://tartiflette.org/", 42);

            ubyte[36] buffer;
            
            BinaryEncoder be;
            ubyte[] remaining = be.encode!ExpandedNodeId(buffer, en);

            assert (remaining.length == 1);
            assert (buffer[].equal([0xC1, 0, 0x01, 0x04, 0x17, 0, 0, 0, 0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x74, 
                                    0x61, 0x72, 0x74, 0x69, 0x66, 0x6c, 0x65, 0x74, 0x74, 0x65, 0x2e, 0x6f, 0x72, 0x67, 
                                    0x2f, 0x2A, 0, 0, 0, 0]));
        }
    }


    /** 
     * Encode an DiagnosticInfo value
     *
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
    ubyte[] encode(T)(return scope ubyte[] buffer, T value,
            Flag!"symbolicId" symbolicId, 
            Flag!"namespace" namespace,
            Flag!"localizedText" localizedText,
            Flag!"locale" locale,
            Flag!"additionalInfo" additionalInfo, 
            Flag!"innerStatusCode" innerStatusCode,
            Flag!"innerDiagnosticInfo" innerDiagnosticInfo) scope if (is(T == DiagnosticInfo))
    {
        
        ubyte encodingMask; // A bit mask that indicates which fields are present in the stream

        enum // bit mask values
        {
            HasSymbolicId          = 0x01,
            HasNamespace           = 0x02,
            HasLocalizedText       = 0x04,
            HasLocale              = 0x08,
            HasAdditionalInfo      = 0x10,
            HasInnerStatusCode     = 0x20,
            HasInnerDiagnosticInfo = 0x40
        }

        size_t neededSpace = 1;  // number of bytes needed in buffer to encode value

        if (symbolicId) 
        {
            encodingMask |= HasSymbolicId;
            neededSpace += int.sizeof;
        }

        if (namespace) 
        {
            encodingMask |= HasNamespace;
            neededSpace += int.sizeof;
        }

        if (localizedText)
        {
            encodingMask |= HasLocalizedText;
            neededSpace += int.sizeof;
        }

        if (locale) 
        {
            encodingMask |= HasLocale;
            neededSpace += int.sizeof;
        }

        if (additionalInfo) 
        {
            encodingMask |= HasAdditionalInfo;
            neededSpace += int.sizeof + value.additionalInfo.length;
        }

        if (innerStatusCode)
        {
            encodingMask |= HasInnerStatusCode;
            neededSpace += int.sizeof;
        }

        if (innerDiagnosticInfo && value.innerDiagnosticInfo !is null)
        {
            encodingMask |= HasInnerDiagnosticInfo;
            // Don't increment needed space here, as it will be done recursively
        }

        enforce!DuaBadEncodingException(buffer.length >= neededSpace, "No space left to encode value");

        buffer[0] = encodingMask;
        buffer = buffer[1 .. $];

        if (symbolicId)
            buffer = encode!int(buffer, value.symbolicId);
        
        if (namespace)
            buffer = encode!int(buffer, value.namespaceUri);
        
        if (locale)
            buffer = encode!int(buffer, value.locale);
        
        if (localizedText)
            buffer = encode!int(buffer, value.localizedText);

        if (additionalInfo)
            buffer = encode!string(buffer, value.additionalInfo);

        if (innerStatusCode)
            buffer = encode!StatusCode(buffer, value.innerStatusCode);

        if (innerDiagnosticInfo && value.innerDiagnosticInfo !is null)
            buffer = encode!DiagnosticInfo(buffer, value, symbolicId, namespace, localizedText, locale,
                                           additionalInfo, innerStatusCode, innerDiagnosticInfo);
    
        return buffer;
    }

    unittest 
    {
        ubyte[9] buffer;
        auto di = DiagnosticInfo(3, 12);

        BinaryEncoder be;
        ubyte[] remaining = be.encode!DiagnosticInfo(buffer, di, Yes.symbolicId, Yes.namespace, No.localizedText, 
                                                     No.locale, No.additionalInfo, No.innerStatusCode, 
                                                     No.innerDiagnosticInfo );

        assert (buffer[].equal([0x03, 0x0C, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00]));
        assert (remaining.length == 0);
    }

    /** 
     * Encode an QualifiedName value
     *
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
            if (is(T == QualifiedName))
    {
        size_t neededSpace = ushort.sizeof + int.sizeof + value.name.length;
        enforce!DuaBadEncodingException(buffer.length >= neededSpace, "No space left to encode value");

        buffer = encode!ushort(buffer, value.namespaceIndex);
        return  encode!string(buffer, value.name);
    }

    unittest 
    {
        ubyte[16] buffer;
        auto qn = QualifiedName(5, "ABBA");

        BinaryEncoder be;
        ubyte[] remaining = be.encode!QualifiedName(buffer, qn);

        assert (remaining.length == 6);
        assert (buffer[].equal([0x05, 0x00, 0x04, 0x00, 0x00, 0x00, 
                                0x41, 0x42, 0x42, 0x41, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]));
    }


    /** 
     * Encode an LocalizedText value
     *
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
            if (is(T == LocalizedText))
    {
        ubyte encodingByte = 0;

        if (value.locale !is null && value.locale.length > 0)
        {
            encodingByte |= 0x01;
        }

        if (value.text !is null && value.text.length > 0)
        {
            encodingByte |= 0x02;
        }

        // encoding byte 
        buffer[0] = encodingByte;
        buffer = buffer [1 .. $];

        // locale 
        if (encodingByte & 0x01)
        {
            buffer = encode!string(buffer, value.locale);
        }

        // text
        if (encodingByte & 0x02)
        {
            buffer = encode!string(buffer, value.text);
        }

        return buffer;
    }

    unittest
    {
        // text
        {
            ubyte[10] buffer;
            auto qn = LocalizedText("ABBA", null);

            BinaryEncoder be;
            ubyte[] remaining = be.encode!LocalizedText(buffer, qn);

            assert (remaining.length == 1);
            assert (buffer[].equal([0x02, 0x04, 0x00, 0x00, 0x00, 0x41, 0x42, 0x42, 0x41, 0x00]));
        }

        // locale 
        {
            ubyte[10] buffer;
            auto qn = LocalizedText(null, "fr_FR");

            BinaryEncoder be;
            ubyte[] remaining = be.encode!LocalizedText(buffer, qn);

            assert (remaining.length == 0);
            assert (buffer[].equal([0x01, 0x05, 0x00, 0x00, 0x00, 0x66, 0x72, 0x5F, 0x46, 0x52]));
        }

        // both 
        {
            ubyte[20] buffer;
            auto qn = LocalizedText("ABBA", "fr_FR");

            BinaryEncoder be;
            ubyte[] remaining = be.encode!LocalizedText(buffer, qn);

            assert (remaining.length == 2);
            assert (buffer[].equal([0x03, 0x05, 0x00, 0x00, 0x00, 0x66, 0x72, 0x5F, 0x46, 0x52, 
                                    0x04, 0x00, 0x00, 0x00, 0x41, 0x42, 0x42, 0x41, 0x00, 0x00]));
        }
    }
}


struct BinaryDecoder
{

    /** 
     * Decode a boolean value
     * 
     * A Boolean value shall be encoded as a single byte where a value of 0 (zero) is false and any non-zero 
     * value is true. 
     *
     * Encoders shall use the value of 1 to indicate a true value; however, decoders shall treat any non-zero 
     * value as true. 
     * 
     * This function reads the value at the beginning of provided buffer then returns the remaining window 
     * of the buffer. 
     * 
     * Params: 
     *     T = The type to encode
     *     buffer = Buffer where to encode the value
     *     value = Value where to store decoded value 
     * 
     * Returns:
     *     The remaining part of the buffer after the read value
     *
     * Throws: 
     *     DuaBadEncodingException if there is not enough space left in the buffer.
     */
    static inout(ubyte)[] decode(T)(return scope inout(ubyte)[] buffer, out T value) if (is(T == bool))
    {
        enforce!DuaBadEncodingException(buffer.length >= 1, "No space left to decode value");

        value = (buffer[0] != 0);
        return buffer[1 .. $];
    }

    unittest 
    {
        ubyte[5] buffer = [0x01, 0x00, 0x00, 0x00, 0x00];
        bool value;
        auto remaining = BinaryDecoder.decode(buffer, value);

        assert (remaining.length == 4);
        assert (value);

        remaining = BinaryDecoder.decode(remaining, value);
        assert (remaining.length == 3);
        assert (!value);
    }


    /** 
     * Decode an integral or floating point value
     * 
     * This function reads the value at the beginning of provided buffer then returns the remaining window 
     * of the buffer. 
     * 
     * Params: 
     *     T = The type to encode
     *     buffer = Buffer where to encode the value
     *     value = Value where to store decoded value 
     * 
     * Returns:
     *     The remaining part of the buffer after the read value
     *
     * Throws: 
     *     DuaBadEncodingException if there is not enough space left in the buffer.
     */
    static inout(ubyte)[] decode(T)(return scope inout(ubyte)[] buffer, out T value) 
            if (isIntegral!T || isFloatingPoint!T)
    {
        enforce!DuaBadEncodingException(buffer.length >= T.sizeof, "No space left to decode value");

        value = std.bitmanip.read!(T, Endian.littleEndian)(buffer);
        return buffer;
    }

    unittest 
    {
        uint value;
        ubyte[5] buffer = [0xBE, 0xBA, 0xFE, 0xCA, 0x00];
        auto remaining = BinaryDecoder.decode(buffer, value);

        assert (remaining.length == 1);
        assert (value == 0xCAFEBABE);
    }

    /** 
     * Decode a string value
     * 
     * This function reads the value at the beginning of provided buffer then returns the remaining window 
     * of the buffer. 
     * 
     * Params: 
     *     T = The type to encode
     *     buffer = Buffer where to encode the value
     *     value = Value where to store decoded value 
     * 
     * Returns:
     *     The remaining part of the buffer after the read value
     *
     * Throws: 
     *     DuaBadEncodingException if there is not enough space left in the buffer.
     */
    static inout(ubyte)[] decode(T)(return scope inout(ubyte)[] buffer, out T value) 
            if (is(T == string) || is(T == bstring))
    {
        enforce!DuaBadEncodingException(buffer.length >= int.sizeof, "No space left to decode value");

        int len = std.bitmanip.read!(int, Endian.littleEndian)(buffer);

        // -1 means null
        if (len == -1)
        {
            value = null;
            return buffer;
        }

        enforce!DuaBadEncodingException(buffer.length >= len, "No space left to decode value");

        () @trusted 
        { 
            auto temp = new Unconst!(ForeachType!T)[len];
            temp[0 .. len] = cast(Unconst!(ForeachType!T)[]) (buffer[0 .. len]); 
            value = assumeUnique(temp);
        }();
        

        return buffer[len .. $];
    }

    unittest 
    {
        // check null 
        {
            string value;
            ubyte[4] buffer = [0xFF, 0xFF, 0xFF, 0xFF];

            auto remaining = decode(buffer[], value);
            assert (remaining.length == 0);
            assert (value is null);
        }

        // check string 
        {
            string value;
            ubyte[8] buffer = [0x04, 0x00, 0x00, 0x00, 0x41, 0x42, 0x42, 0x41];

            auto remaining = decode(buffer[], value);
            assert (remaining.length == 0);
            assert (value == "ABBA");
        }
    }

}