module dua.protocol.message;

import dua.encoding.binary;
import dua.except;
import std.exception;

version (unittest)
{
    import std.algorithm.comparison : equal;
}

/** 
 * Every OPC UA Connection Protocol Message has a header 
 */
struct MessageHeader
{
    /** 
     *  The first three bytes identify the Message type.
     *
     *  The following values are defined at this time:
     *  - HEL a HelloMessage
     *  - ACK an AcknowledgeMessage
     *  - ERR an ErrorMessage
     *  - RHE a ReverseHelloMessage
     * 
     *  The Fourth byte must be set to ASCII code to 'F'.
     */
    ubyte[4] messageType;

    /// The length of the Message, in bytes. This value includes the 8 bytes for the Message header. 
    uint messageSize;
}


/** 
 * The Hello message
 */
struct HelloMessage
{
    /// Protocol version requested by the client
    uint protocolVersion;
    /// The largest message chunk the sender can receive
    uint receiveBufferSize;
    /// The largest message chunk the sender will send
    uint sendBufferSize;
    /// The maximum message size for any response message (0 = no limit)
    uint maxMessageSize;
    /// The maximum number of chunks in any response message 
    uint maxChunkCount;
    /// The URL of the EndPoint which the Client wished to connect to.
    string endpointUrl;
}

/** 
 * The acknowledge message
 */
struct AcknowledgeMessage
{
    /** 
     * A protocol version supported by the Server that is less than or equal to the protocol version requested 
     * in the Hello Message. 
     */
    uint protocolVersion;
    /// The largest message chunk the sender can receive
    uint receiveBufferSize;
    /// The largest message chunk the sender will send
    uint sendBufferSize;
    /// The maximum message size for any request message (0 = no limit)
    uint maxMessageSize;
    /// The maximum number of chunks in any request message 
    uint maxChunkCount;
}

/** 
 * The Error message
 */
struct ErrorMessage
{
    /// The numeric code for the error
    uint error;
    /// A more verbose description of the error. No more than 4096 bytes.
    string reason;
}


/** 
 * The Reverse Hello message
 */
struct ReverseHelloMessage
{
    /// The application URI of the server which sent the message 
    string serverUri;
    /// The URL of the endpoint which the client uses when establishing the SecureChannel
    string endpointUrl;
}


/** 
 * Interface for encoding messages
 *
 */
interface MessageEncoder
{
    /** 
     * Encode a Hello Message 
     * 
     * Params: 
     *     buffer = Byte buffer where to encode message 
     *     msg = Message to encode 
     * 
     * Returns: 
     *     Returns the remaining buffer (after the encoding of the message)
     */
    ubyte[] encodeHelloMessage(return scope ubyte[] buffer, ref const(HelloMessage) msg);

    /** 
     * Encode a Acknowledgement Message 
     * 
     * Params: 
     *     buffer = Byte buffer where to encode message 
     *     msg = Message to encode 
     * 
     * Returns: 
     *     Returns the remaining buffer (after the encoding of the message)
     */
    ubyte[] encodeAckMessage(return scope ubyte[] buffer, ref const(AcknowledgeMessage) msg);

    /** 
     * Encode an Error Message 
     * 
     * Params: 
     *     buffer = Byte buffer where to encode message 
     *     msg = Message to encode 
     * 
     * Returns: 
     *     Returns the remaining buffer (after the encoding of the message)
     */
    ubyte[] encodeErrMessage(return scope ubyte[] buffer, ref const(ErrorMessage) msg);

    /** 
     * Encode a ReverseHello Message 
     * 
     * Params: 
     *     buffer = Byte buffer where to encode message 
     *     msg = Message to encode 
     * 
     * Returns: 
     *     Returns the remaining buffer (after the encoding of the message)
     */
    ubyte[] encodeReverseHello(return scope ubyte[] buffer, ref const(ReverseHelloMessage) msg);
}

/** 
 * Interface for decoding messages
 *
 */
interface MessageDecoder
{

    /** 
     * Decode a Hello Message 
     * 
     * Params: 
     *     buffer = Byte buffer from which to encode message 
     *     msg = Message to decode 
     * 
     * Returns: 
     *     Returns the remaining buffer (after the decoding of the message)
     */
    inout(ubyte)[] decodeHelloMessage(return scope inout(ubyte)[] buffer, out HelloMessage msg);

    /** 
     * Decode a Acknowledgement Message 
     * 
     * Params: 
     *     buffer = Byte buffer from which to encode message 
     *     msg = Message to decode 
     * 
     * Returns: 
     *     Returns the remaining buffer (after the decoding of the message)
     */
    inout(ubyte)[] decodeAckMessage(return scope inout(ubyte)[] buffer, out AcknowledgeMessage msg);

    /** 
     * Decode an Error Message 
     * 
     * Params: 
     *     buffer = Byte buffer from which to encode message 
     *     msg = Message to decode 
     * 
     * Returns: 
     *     Returns the remaining buffer (after the decoding of the message)
     */
    inout(ubyte)[] decodeErrorMessage(return scope inout(ubyte)[] buffer, out ErrorMessage msg);

    /** 
     * Decode a Reverse Hello Message 
     * 
     * Params: 
     *     buffer = Byte buffer from which to encode message 
     *     msg = Message to decode 
     * 
     * Returns: 
     *     Returns the remaining buffer (after the decoding of the message)
     */
    inout(ubyte)[] decodeReverseHelloMessage(return scope inout(ubyte)[] buffer, out ReverseHelloMessage msg);
}


/** 
 * Implementation of MessageEncoder for the opc-ua binary protocol.
 */
final class BinaryMessageEncoder : MessageEncoder
{
    enum HEADER_SIZE = 8;

    /** 
     * Encode a Hello Message in binary format.
     * 
     * Params: 
     *     buffer = Byte buffer where to encode message 
     *     msg = Message to encode 
     * 
     * Returns: 
     *     Returns the remaining buffer (after the encoding of the message)
     */
    override ubyte[] encodeHelloMessage(return scope ubyte[] buffer, ref const(HelloMessage) msg)
    {
        buffer = writeMessageHeader(buffer, msg);

        foreach (field; msg.tupleof)
        {
            buffer = BinaryEncoder.encode(buffer, field);
        }

        return buffer;
    }

    unittest 
    {
        auto msg = HelloMessage(3, 16, 16, 32, 8, "ABBA");
        ubyte[36] buffer;

        scope encoder = new BinaryMessageEncoder;
        ubyte[] remaining = encoder.encodeHelloMessage(buffer[], msg);

        assert (remaining.length == 0);
        assert (buffer[].equal([ 0x48, 0x45, 0x4C, 0x46, 0x24, 0x00, 0x00, 0x00,
                                 0x03, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00,
                                 0x10, 0x00, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00,
                                 0x08, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 
                                 0x41, 0x42, 0x42, 0x41 ]));
    }

    /** 
     * Encode a Acknowledgement Message in binary format.
     * 
     * Params: 
     *     buffer = Byte buffer where to encode message 
     *     msg = Message to encode 
     * 
     * Returns: 
     *     Returns the remaining buffer (after the encoding of the message)
     */
    override ubyte[] encodeAckMessage(return scope ubyte[] buffer, ref const(AcknowledgeMessage) msg)
    {
        buffer = writeMessageHeader(buffer, msg);

        foreach (field; msg.tupleof)
        {
            buffer = BinaryEncoder.encode(buffer, field);
        }

        return buffer;
    }

    unittest 
    {
        auto msg = AcknowledgeMessage(4, 32, 32, 16, 8);
        scope encoder = new BinaryMessageEncoder;
        ubyte[32] buffer;
        ubyte[] remaining = encoder.encodeAckMessage(buffer[], msg);

        assert (remaining.length == 4);
        assert (buffer[].equal([ 0x41, 0x43, 0x4B, 0x46, 0x1C, 0x00, 0x00, 0x00,
                                 0x04, 0x00, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 
                                 0x20, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 
                                 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ]));


    }

    /** 
     * Encode an Error Message 
     * 
     * Params: 
     *     buffer = Byte buffer where to encode message 
     *     msg = Message to encode 
     * 
     * Returns: 
     *     Returns the remaining buffer (after the encoding of the message)
     */
    override ubyte[] encodeErrMessage(return scope ubyte[] buffer, ref const(ErrorMessage) msg)
    {
        buffer = writeMessageHeader(buffer, msg);

        foreach (field; msg.tupleof)
        {
            buffer = BinaryEncoder.encode(buffer, field);
        }

        return buffer;
    }

    unittest 
    {
        auto msg = ErrorMessage(404, "Not found");
        scope encoder = new BinaryMessageEncoder;
        ubyte[32] buffer;
        ubyte[] remaining = encoder.encodeErrMessage(buffer[], msg);

        assert (remaining.length == 7);
        assert (buffer[].equal([ 0x45, 0x52, 0x52, 0x46, 0x19, 0x00, 0x00, 0x00,
                                 0x94, 0x01, 0x00, 0x00, 0x09, 0x00, 0x00, 0x00, 
                                 0x4E, 0x6F, 0x74, 0x20, 0x66, 0x6F, 0x75, 0x6E,
                                 0x64, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ]));
    }

    /** 
     * Encode a ReverseHello Message 
     * 
     * Params: 
     *     buffer = Byte buffer where to encode message 
     *     msg = Message to encode 
     * 
     * Returns: 
     *     Returns the remaining buffer (after the encoding of the message)
     */
    override ubyte[] encodeReverseHello(return scope ubyte[] buffer, ref const(ReverseHelloMessage) msg)
    {
        buffer = writeMessageHeader(buffer, msg);

        foreach (field; msg.tupleof)
        {
            buffer = BinaryEncoder.encode(buffer, field);
        }

        return buffer;
    }

    unittest 
    {
        auto msg = ReverseHelloMessage("ABBA", "TEST");
        scope encoder = new BinaryMessageEncoder;
        ubyte[24] buffer;
        ubyte[] remaining = encoder.encodeReverseHello(buffer[], msg);

        assert (remaining.length == 0);
        assert (buffer[].equal([ 0x52, 0x48, 0x45, 0x46, 0x18, 0x00, 0x00, 0x00,
                                 0x04, 0x00, 0x00, 0x00, 0x41, 0x42, 0x42, 0x41, 
                                 0x04, 0x00, 0x00, 0x00, 0x54, 0x45, 0x53, 0x54 ]));
    }

private:

    static ubyte[] writeMessageHeader(return scope ubyte[] buffer, ref const(HelloMessage) msg)
    {
        // write message type
        buffer[0] = 'H';
        buffer[1] = 'E';
        buffer[2] = 'L';
        buffer[3] = 'F';
        buffer = buffer[4 .. $];

        // calculate message size
        size_t neededSpace = HEADER_SIZE;

        foreach (field; msg.tupleof)
        {
            neededSpace += BinaryEncoder.encodeSize(field);
        }

        buffer = BinaryEncoder.encode(buffer, cast(uint) neededSpace);

        return buffer;
    }

    static ubyte[] writeMessageHeader(return scope ubyte[] buffer, ref const(AcknowledgeMessage) msg)
    {
        // write message type
        buffer[0] = 'A';
        buffer[1] = 'C';
        buffer[2] = 'K';
        buffer[3] = 'F';
        buffer = buffer[4 .. $];

        // calculate message size
        size_t neededSpace = HEADER_SIZE;

        foreach (field; msg.tupleof)
        {
            neededSpace += BinaryEncoder.encodeSize(field);
        }

        buffer = BinaryEncoder.encode(buffer, cast(uint) neededSpace);

        return buffer;
    }

    static ubyte[] writeMessageHeader(return scope ubyte[] buffer, ref const(ErrorMessage) msg)
    {
        // write message type
        buffer[0] = 'E';
        buffer[1] = 'R';
        buffer[2] = 'R';
        buffer[3] = 'F';
        buffer = buffer[4 .. $];

        // calculate message size
        size_t neededSpace = HEADER_SIZE;

        foreach (field; msg.tupleof)
        {
            neededSpace += BinaryEncoder.encodeSize(field);
        }

        buffer = BinaryEncoder.encode(buffer, cast(uint) neededSpace);

        return buffer;
    }

    static ubyte[] writeMessageHeader(return scope ubyte[] buffer, ref const(ReverseHelloMessage) msg)
    {
        // write message type
        buffer[0] = 'R';
        buffer[1] = 'H';
        buffer[2] = 'E';
        buffer[3] = 'F';
        buffer = buffer[4 .. $];

        // calculate message size
        size_t neededSpace = HEADER_SIZE;

        foreach (field; msg.tupleof)
        {
            neededSpace += BinaryEncoder.encodeSize(field);
        }

        buffer = BinaryEncoder.encode(buffer, cast(uint) neededSpace);

        return buffer;
    }
}


/** 
 * Implementation of MessageDecoder for the opc-ua binary protocol.
 */
final class BinaryMessageDecoder : MessageDecoder
{
    enum HEADER_SIZE = 8;

    /** 
     * Decode a Hello Message 
     * 
     * Params: 
     *     buffer = Byte buffer from which to encode message 
     *     msg = Message to decode 
     * 
     * Returns: 
     *     Returns the remaining buffer (after the decoding of the message)
     */
    inout(ubyte)[] decodeHelloMessage(return scope inout(ubyte)[] buffer, out HelloMessage msg)
    {
        MessageHeader hdr;
        buffer = decodeHeader(buffer, hdr);

        enforce!DuaBadDecodingException(hdr.messageType[] == ['H', 'E', 'L', 'F']);
        enforce!DuaBadDecodingException(buffer.length >= (hdr.messageSize - HEADER_SIZE), "Not enough space");

        buffer = BinaryDecoder.decode!uint(buffer, msg.protocolVersion);
        buffer = BinaryDecoder.decode!uint(buffer, msg.receiveBufferSize);
        buffer = BinaryDecoder.decode!uint(buffer, msg.sendBufferSize);
        buffer = BinaryDecoder.decode!uint(buffer, msg.maxMessageSize);
        buffer = BinaryDecoder.decode!uint(buffer, msg.maxChunkCount);
        buffer = BinaryDecoder.decode!string(buffer, msg.endpointUrl);

        return buffer;
    }

    unittest 
    {
        ubyte[36] buffer = [ 0x48, 0x45, 0x4C, 0x46, 0x24, 0x00, 0x00, 0x00,
                             0x03, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00,
                             0x10, 0x00, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00,
                             0x08, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 
                             0x41, 0x42, 0x42, 0x41 ];
        
        scope decoder = new BinaryMessageDecoder;
        HelloMessage msg;
        ubyte[] remaining = decoder.decodeHelloMessage(buffer[], msg);

        assert (remaining.length == 0);
        assert (msg == HelloMessage(3, 16, 16, 32, 8, "ABBA"));

    }


    /** 
     * Decode a Acknowledgement Message 
     * 
     * Params: 
     *     buffer = Byte buffer from which to encode message 
     *     msg = Message to decode 
     * 
     * Returns: 
     *     Returns the remaining buffer (after the decoding of the message)
     */
    inout(ubyte)[] decodeAckMessage(return scope inout(ubyte)[] buffer, out AcknowledgeMessage msg)
    {
        MessageHeader hdr;
        buffer = decodeHeader(buffer, hdr);

        enforce!DuaBadDecodingException(hdr.messageType[] == ['A', 'C', 'K', 'F']);
        enforce!DuaBadDecodingException(buffer.length >= (hdr.messageSize - HEADER_SIZE), "Not enough space");

        buffer = BinaryDecoder.decode!uint(buffer, msg.protocolVersion);
        buffer = BinaryDecoder.decode!uint(buffer, msg.receiveBufferSize);
        buffer = BinaryDecoder.decode!uint(buffer, msg.sendBufferSize);
        buffer = BinaryDecoder.decode!uint(buffer, msg.maxMessageSize);
        buffer = BinaryDecoder.decode!uint(buffer, msg.maxChunkCount);

        return buffer;
    }

    unittest 
    {
        ubyte[32] buffer = [ 0x41, 0x43, 0x4B, 0x46, 0x1C, 0x00, 0x00, 0x00,
                             0x04, 0x00, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 
                             0x20, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 
                             0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ];

        
        scope decoder = new BinaryMessageDecoder;
        AcknowledgeMessage msg;
        ubyte[] remaining = decoder.decodeAckMessage(buffer[], msg);

        assert (remaining.length == 4);
        assert (msg == AcknowledgeMessage(4, 32, 32, 16, 8));
    }


    /** 
     * Decode an Error Message 
     * 
     * Params: 
     *     buffer = Byte buffer from which to encode message 
     *     msg = Message to decode 
     * 
     * Returns: 
     *     Returns the remaining buffer (after the decoding of the message)
     */
    inout(ubyte)[] decodeErrorMessage(return scope inout(ubyte)[] buffer, out ErrorMessage msg)
    {
        MessageHeader hdr;
        buffer = decodeHeader(buffer, hdr);

        enforce!DuaBadDecodingException(hdr.messageType[] == ['E', 'R', 'R', 'F']);
        enforce!DuaBadDecodingException(buffer.length >= (hdr.messageSize - HEADER_SIZE), "Not enough space");

        buffer = BinaryDecoder.decode!uint(buffer, msg.error);
        buffer = BinaryDecoder.decode!string(buffer, msg.reason);

        return buffer;
    }

    unittest 
    {
        const(ubyte)[32] buffer = [ 0x45, 0x52, 0x52, 0x46, 0x19, 0x00, 0x00, 0x00,
                                    0x94, 0x01, 0x00, 0x00, 0x09, 0x00, 0x00, 0x00, 
                                    0x4E, 0x6F, 0x74, 0x20, 0x66, 0x6F, 0x75, 0x6E,
                                    0x64, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ];

        scope decoder = new BinaryMessageDecoder;
        ErrorMessage msg;
        const(ubyte)[] remaining = decoder.decodeErrorMessage(buffer[], msg);

        assert (remaining.length == 7);
        assert (msg == ErrorMessage(404, "Not found"));
    }


    /** 
     * Decode a Reverse Hello Message 
     * 
     * Params: 
     *     buffer = Byte buffer from which to encode message 
     *     msg = Message to decode 
     * 
     * Returns: 
     *     Returns the remaining buffer (after the decoding of the message)
     */
    inout(ubyte)[] decodeReverseHelloMessage(return scope inout(ubyte)[] buffer, out ReverseHelloMessage msg)
    {
        MessageHeader hdr;
        buffer = decodeHeader(buffer, hdr);

        enforce!DuaBadDecodingException(hdr.messageType[] == ['R', 'H', 'E', 'F']);
        enforce!DuaBadDecodingException(buffer.length >= (hdr.messageSize - HEADER_SIZE), "Not enough space");

        buffer = BinaryDecoder.decode!string(buffer, msg.serverUri);
        buffer = BinaryDecoder.decode!string(buffer, msg.endpointUrl);

        return buffer;
    }

    unittest 
    {
        immutable(ubyte)[24] buffer = [ 0x52, 0x48, 0x45, 0x46, 0x18, 0x00, 0x00, 0x00,
                                        0x04, 0x00, 0x00, 0x00, 0x41, 0x42, 0x42, 0x41, 
                                        0x04, 0x00, 0x00, 0x00, 0x54, 0x45, 0x53, 0x54 ];
        
        ReverseHelloMessage msg;
        scope decoder = new BinaryMessageDecoder;
        immutable(ubyte)[] remaining = decoder.decodeReverseHelloMessage(buffer, msg);

        assert (remaining.length == 0);
        assert (msg == ReverseHelloMessage("ABBA", "TEST"));
    }


private:

    static inout(ubyte)[] decodeHeader(return scope inout(ubyte)[] buffer, out MessageHeader hdr)
    {
        enforce!DuaBadDecodingException(buffer.length >= HEADER_SIZE, "Not enough space");

        buffer = BinaryDecoder.decode!ubyte(buffer, hdr.messageType[0]);
        buffer = BinaryDecoder.decode!ubyte(buffer, hdr.messageType[1]);
        buffer = BinaryDecoder.decode!ubyte(buffer, hdr.messageType[2]);
        buffer = BinaryDecoder.decode!ubyte(buffer, hdr.messageType[3]);
        buffer = BinaryDecoder.decode!uint(buffer, hdr.messageSize);

        return buffer;
    }
}

