module dua.node;

import dua.except;

import std.algorithm.comparison;
import std.algorithm.searching;
import std.base64;
import std.conv;
import std.exception;
import std.format;
import std.sumtype;
import std.traits;
import std.typecons : isBitFlagEnum;
import std.uuid;

@safe:


/**
 * Structure to store the unique identifier of a node in the server address space.
 */
struct NodeId 
{
    /// Alias for byte string
    alias bstring = immutable(ubyte)[];

    /// A nodeId Identifier is either an integer, a string, a UUID or a byte string
    alias Identifier = SumType!(uint, string, UUID, bstring);

    /**
     * Construct a numeric identifier.
     * 
     * Params:
     *     nsIdx = Namespace index
     *     val = int value
     */
    this(int nsIdx, uint val) pure
    in (nsIdx >= 0 && nsIdx <= ushort.max)
    {
        namespaceIndex = cast(ushort) nsIdx;
        identifier = Identifier(val);
    }

    unittest 
    {
        auto n1 = NodeId(2, 5001);
    }

    /**
     * Construct a string identifier.
     * 
     * Params:
     *     nsIdx = Namespace index
     *     val = string value
     */
    this(int nsIdx, string val) pure
    in (nsIdx >= 0 && nsIdx <= ushort.max)
    in (val !is null && val.length > 0)
    {
        namespaceIndex = cast(ushort) nsIdx;
        identifier = Identifier(val);
    }

    unittest 
    {
        auto n2 = NodeId(2, "MyTemperature");
    }

    /**
     * Construct a GUID identifier.
     * 
     * Params: 
     *     nsIdx = Namespace index
     *     val = GUID value
     */
    this(int nsIdx, UUID val) pure
    in (nsIdx >= 0 && nsIdx <= ushort.max)
    {
        namespaceIndex = cast(ushort) nsIdx;
        identifier = Identifier(val);
    }

    unittest 
    {
        auto n3 = NodeId(2, UUID("8AB3060E-2cba-4f23-b74c-b52db3bdfb46"));
    }

    /**
     * Construct an Opaque identifier.
     * 
     * Params:
     *     nsIdx = Namespace index
     *     val = byte string value
     */
    this(int nsIdx, bstring val) pure
    in (nsIdx >= 0 && nsIdx <= ushort.max)
    in (val !is null && val.length > 0)
    {
        namespaceIndex = cast(ushort) nsIdx;
        identifier = Identifier(val);
    }

    unittest 
    {
        bstring val = [12, 28, 2, 9, 21];
        auto n4 = NodeId(2, val);
    }

    /** 
     * Returns the string notation of a NodeId
     */
    string toString() const pure
    {
        return identifier.match!(
            (uint ul) 
            {
                if (namespaceIndex == 0) 
                    return "i=%s".format(ul);
                return "ns=%s;i=%s".format(namespaceIndex, ul);
            },
            (string s)
            {
                if (namespaceIndex == 0) 
                    return "s=%s".format(s);
                return "ns=%s;s=%s".format(namespaceIndex, s);
            },
            (UUID u)
            {
                if (namespaceIndex == 0) 
                    return "g=%s".format(u.toString());
                return "ns=%s;g=%s".format(namespaceIndex, u.toString());
            },
            (bstring bs)
            {
                if (namespaceIndex == 0) 
                    return "b=%s".format(Base64.encode(bs));
                return "ns=%s;b=%s".format(namespaceIndex, Base64.encode(bs));
            }
        );
    }

    unittest 
    {
        string expected = "ns=2;s=MyTemperature";
        assert(NodeId(2, "MyTemperature").toString() == expected);

        expected = "i=2045";
        assert(NodeId(0, 2045).toString() == expected);

        expected = "ns=1;g=09087e75-8e5e-499b-954f-f2a9603db28a";
        assert(NodeId(1, UUID("09087e75-8e5e-499b-954f-f2a9603db28a")).toString() == expected);

        expected = "ns=1;b=M/RbKBsRVkePCePcx24oRA==";
        bstring val = Base64.decode("M/RbKBsRVkePCePcx24oRA==");
        assert(NodeId(1, val).toString() == expected);
    }

    /** 
     * Constructs a NodeId from its textual representation

     * Params:
     *     text = Text to construct a NodeId from.
     * 
     * Returns: 
     *     a NodeId from a textual representation
     *
     * Throws:
     *     DuaBadDecodingException if text could not be decoded correctly
     */
    static NodeId fromString(string text) pure
    {
        try 
        {
            int nsIdx = 0;
            ptrdiff_t limit = -1;

            if (text.startsWith("ns="))
            {
                // Parse namespace index
                limit = text.countUntil(';');
                enforce!DuaBadDecodingException(limit > 3, "Missing namespace index separator");

                nsIdx = to!int(text[3..limit]);
                enforce!DuaBadDecodingException(nsIdx > 0 && nsIdx <= ushort.max, "Namespace index is off limits");
            }

            // parse identifier
            text = text[limit+1 .. $];
      
            switch (text[0])
            {
            case 'i':
                {
                    text = text[2 .. $];
                    uint temp = to!uint(text);
                    return NodeId(nsIdx, temp);
                }
                
            case 's':
                text = text[2 .. $];
                return NodeId(nsIdx, text);

            case 'g':
                text = text[2 .. $];
                return NodeId(nsIdx, UUID(text));

            case 'b':
                text = text[2 .. $];
                return NodeId(nsIdx, Base64.decode(text));

            default:
                throw new DuaBadDecodingException("Malformed node id representation: %s".format(text));
            }
        }
        catch (Exception e)
        {
            throw new DuaBadDecodingException("Conversion error: %s".format(e.msg));
        }
    }

    unittest 
    {
        // Check all the valid possibilities
        {
            string text = "ns=2;s=MyTemperature";
            NodeId value = NodeId.fromString(text);
            NodeId expected = NodeId(2, "MyTemperature");
            assert (value == expected);
        }

        {
            string text = "s=MyTemperature";
            NodeId value = NodeId.fromString(text);
            NodeId expected = NodeId(0, "MyTemperature");
            assert (value == expected);
        }

        {
            string text = "i=5001";
            NodeId value = NodeId.fromString(text);
            NodeId expected = NodeId(0, 5001);
            assert (value == expected);
        }

        {
            string text = "ns=2;i=5001";
            NodeId value = NodeId.fromString(text);
            NodeId expected = NodeId(2, 5001);
            assert (value == expected);
        }

        {
            string text = "ns=2;g=09087e75-8e5e-499b-954f-f2a9603db28a";
            NodeId value = NodeId.fromString(text);
            NodeId expected = NodeId(2, UUID("09087e75-8e5e-499b-954f-f2a9603db28a"));
            assert (value == expected);
        }

        {
            string text = "g=09087e75-8e5e-499b-954f-f2a9603db28a";
            NodeId value = NodeId.fromString(text);
            NodeId expected = NodeId(0, UUID("09087e75-8e5e-499b-954f-f2a9603db28a"));
            assert (value == expected);
        }

        {
            string text = "ns=1;b=M/RbKBsRVkePCePcx24oRA==";
            NodeId value = NodeId.fromString(text);
            NodeId expected = NodeId(1, Base64.decode("M/RbKBsRVkePCePcx24oRA=="));
            assert (value == expected);
        }

        {
            string text = "b=M/RbKBsRVkePCePcx24oRA==";
            NodeId value = NodeId.fromString(text);
            NodeId expected = NodeId(0, Base64.decode("M/RbKBsRVkePCePcx24oRA=="));
            assert (value == expected);
        }

        // Test some invalid values
        assertThrown!DuaBadDecodingException(NodeId.fromString("ThisisANonValidString"));
        assertThrown!DuaBadDecodingException(NodeId.fromString("i=someLetters"));
        assertThrown!DuaBadDecodingException(NodeId.fromString("i=1341341341341341234134342341341341234134134134414"));
        assertThrown!DuaBadDecodingException(NodeId.fromString("ns=NotNumeric;s=121212"));
        assertThrown!DuaBadDecodingException(NodeId.fromString("ns="));
        assertThrown!DuaBadDecodingException(NodeId.fromString("ns=1;g=ThisIsNotAGUID"));
        assertThrown!DuaBadDecodingException(NodeId.fromString("ns=1;b=Thi[[[["));
    }

    /** 
     * Overloading of == and != operators for NodeId 
     */
    bool opEquals(ref const NodeId other) const pure nothrow @nogc
    {
        return (namespaceIndex == other.namespaceIndex)    
                && (identifier == other.identifier);
    }

    /** 
     * Overloading of hash function.
     */
    size_t toHash() const pure nothrow @nogc
    {
        size_t val = object.hashOf(namespaceIndex);
        return object.hashOf(identifier, val);
    }

    /** 
     * Overloading of <, <=, >= and > operators for NodeId 
     */
    int opCmp(ref const NodeId other) const pure nothrow @nogc
    {
        // compare namespace index
        if (namespaceIndex != other.namespaceIndex)
        {
            return namespaceIndex < other.namespaceIndex ? -1 : 1;
        }

        // compare identifier 
        immutable thisType = this.identifierType;
        immutable otherType = other.identifierType;

        if (thisType != otherType)
        {
            return thisType < otherType ? -1 : 1;
        }

        // compare values together
        alias doMatch = match!(
            (uint a, uint b) 
            { 
                if (a < b) 
                    return -1;
                if (a > b)
                    return 1;
                return 0;
            },
            (string a, string b) => a.cmp(b),
            (UUID a, UUID b) => a.opCmp(b),
            (bstring a, bstring b) => a.cmp(b),
            (a, b) => assert(0)
        );

        return doMatch(this.identifier, other.identifier);
    }


    unittest 
    {
        // first compare by namespace index
        {
            immutable n1 = NodeId(3, 4224);
            immutable n2 = NodeId(12, 4224);

            assert (n1 < n2);
        }

        // then compare by type 
        {
            immutable n1 = NodeId(12, 4224);
            immutable n2 = NodeId(12, "MyTemperature");

            assert (n1 < n2);
        }

        // then compare by value
        {
            immutable n1 = NodeId(12, 4224);
            immutable n2 = NodeId(12, 42);

            assert (n2 < n1);
        }
    }

    int identifierType() const pure nothrow @nogc
    {
        return identifier.match!(
            (uint v) => 1,
            (string v) => 2,
            (UUID v) => 3,
            (bstring v) => 4
        );
    }
    
    /// Namespace index
    ushort namespaceIndex;
    /// Identifier
    Identifier identifier;
}


enum AccessLevel
{
    CurrentRead = 1 << 0,
    CurrentWrite = 1 << 1,
    HistoryRead = 1 << 2,
    HistoryWrite = 1 << 3,
    SemanticChange = 1 << 4,
    StatusWrite = 1 << 5,
    TimestameWrite = 1 << 6 
}

enum WriteMask 
{
    AccessLevel = 1 << 0,
    ArrayDimensions = 1 << 1,
    BrowseName = 1 << 2,
    ContainsNoLoops = 1 << 3,
    DataType = 1 << 4,
    Description = 1 << 5,
    DisplayName = 1 << 6,
    EventNotifier = 1 << 7,
    Executable = 1 << 8,
    Historizing = 1 << 9,
    InverseName = 1 << 10,
    IsAbstract = 1 << 11,
    MinimumSamplingInterval = 1 << 12,
    NodeClass = 1 << 13,
    NodeId = 1 << 14,
    Symmetric = 1 << 15,
    UserAccessLevel = 1 << 16,
    UserExecutable = 1 << 17,
    UserWriteMask = 1 << 18,
    ValueRank = 1 << 19,
    WriteMask = 1 << 20,
    ValueForVariableType = 1 << 21
}

enum EventNotifier
{
    SubscribeToEvents = 1 << 0,
    HistoryRead = 1 << 2,
    HistoryWrite = 1 << 3
}


/** 
 * From an integral value, returns a forward Range iterating over each enum value 
 * for which the corresponding bit is set.
 * 
 * Params: 
 *     value = An integral value representing values of enum E or'ed together
 *
 * Returns:
 *     A forward range iterating over the values of enum E or'ed together.
 */
auto parseBitfield(E)(OriginalType!E value) 
        if (isIntegral!(OriginalType!E) && isBitFlagEnum!E)
{
    struct EnumIterator
    {
        this(OriginalType!E val)
        {
            foreach (i, e; EnumMembers!E)
            {
                values[i] = e;
            }

            value = val;
            moveToNextValue();
        }

        auto save()
        {
            return this;
        }

        bool empty() const 
        {
            return index >= values.length;
        }

        E front() const 
        {
            return values[index];
        }

        void popFront()
        {
            index++;
            moveToNextValue();
        }

    private:
        void moveToNextValue()
        {
            while ((index < values.length) && !(values[index] & value))
            {
                index++;
            }
        }

        size_t index;
        E[EnumMembers!E.length] values;
        OriginalType!E value;
    }

    return EnumIterator(value);
}

unittest
{
    // Check with three values
    int val = AccessLevel.CurrentRead | AccessLevel.CurrentWrite | AccessLevel.HistoryRead;
    auto range = parseBitfield!(AccessLevel)(val);
    assert (range.equal([AccessLevel.CurrentRead, 
                        AccessLevel.CurrentWrite, 
                        AccessLevel.HistoryRead]));

    // Check with empty value
    val = 0;
    range = parseBitfield!(AccessLevel)(val);
    assert (range.empty);
}

enum AttributeId
{
    NodeId = 1,
    NodeClass = 2,
    BrowseName = 3,
    DisplayName = 4,
    Description = 5,
    WriteMask = 6,
    UserWriteMask = 7,
    IsAbstract = 8,
    Symmetric = 9,
    InverseName = 10,
    ContainsNoLoops = 11,
    EventNotifier = 12,
    Value = 13,
    DataType = 14,
    ValueRank = 15,
    ArrayDimensions = 16,
    AccessLevel = 17,
    UserAccessLevel = 18,
    MinimumSamplingInterval = 19,
    Historizing = 20,
    Executable = 21,
    UserExecutable = 22,
    DataTypeDefinition = 23,
    RolePermissions = 24,
    UserRolePermissions = 25,
    AccessRestrictions = 26,
    AccessLevelEx = 27
}


abstract class Node 
{
    /**
     * Node equality operator 
     * 
     * Two nodes are considered equal if they have the same NodeId
     * 
     */
    override bool opEquals(Object other) const @nogc pure nothrow
    {
        auto otherNode = cast(Node)other;
        return otherNode !is null && m_nodeId == otherNode.m_nodeId;
    }

    /** 
     * Node Hash function
     */
    override size_t toHash() const @nogc pure nothrow
    {
        return m_nodeId.toHash();
    }

    /** 
     * Returns this node identifier.
     */
    NodeId id() const 
    {
        return m_nodeId;
    }

private:
    NodeId m_nodeId;
}


/** 
 * A qualified name is a (namespaceIndex, name) pair.
 */
struct QualifiedName 
{
    /// Index that identifies the namespace that defines the name. 
    ushort namespaceIndex;

    /// The text portion of the QualifiedName.
    string name; 

    /** 
     * Constructs a QualifiedName object from a string 
     *
     * A textual representation consists in a 
     * 
     * Params: 
     *     value = Textual representation of a qualified name.
     *
     * Returns: 
     *     A QualifiedName structure from the representation
     */
    static QualifiedName fromString(string value) pure 
    {
        ptrdiff_t index = value.countUntil(':');

        if (index == -1)
        {
            return QualifiedName(0, value);
        }
        else 
        {
            try 
            {
                ushort idx = value[0 .. index].to!ushort;
                string text = value[index+1 .. $];
                return QualifiedName(idx, text);
            }
            catch (ConvException e)
            {
                throw new DuaBadDecodingException("Cannot decode QualifiedName from string");
            }
        }
    }

    unittest 
    {
        // Test with no namespace index
        {
            auto qn = QualifiedName.fromString("Temperature");
            assert (qn.namespaceIndex == 0);
            assert (qn.name == "Temperature");
        }

        // Test with namespace index 
        {
            auto qn = QualifiedName.fromString("2:Temperature");
            assert (qn.namespaceIndex == 2);
            assert (qn.name == "Temperature");
        }

        // Test with invalid value throws a Bad Decoding Exception
        {
            assertThrown!DuaBadDecodingException(QualifiedName.fromString("IAmNotAnInteger:"));
        }
    }

    /** 
     * Returns the textual representation of a QualifiedName structure.
     */
    string toString() const 
    {
        if (namespaceIndex != 0)
            return "%d:%s".format(namespaceIndex, name);
        else 
            return name;
    }

    unittest
    {
        // Test with ns = 0
        {
            auto qn = QualifiedName(0, "Temperature");
            assert (qn.toString() == "Temperature");
        }

        // Test with ns = 2
        {
            auto qn = QualifiedName(2, "Temperature");
            assert (qn.toString() == "2:Temperature");
        }
    }

    int opCmp(ref const QualifiedName other) const pure @nogc nothrow
    {
        if (namespaceIndex < other.namespaceIndex)
            return -1;

        if (namespaceIndex > other.namespaceIndex)
            return 1;

        return cmp(name, other.name);    
    }

    unittest 
    {
        auto qn1 = QualifiedName(0, "Temperature");
        auto qn2 = QualifiedName(1, "Temperature");
        auto qn3 = QualifiedName(1, "Temperature");
        auto qn4 = QualifiedName(1, "Temperature1");

        assert (qn1 < qn2);
        assert (qn2 == qn3);
        assert (qn4 > qn3);
    }
}


struct LocalizedText 
{
    string text;
    string locale;
}