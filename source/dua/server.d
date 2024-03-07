module dua.server;

import dua.except;
import std.algorithm.searching;
import std.exception;
import std.format;

@safe:

final class Server
{
    this(string serverUri)
    {
        m_namespaces = ["http://opcfoundation.org/UA/", serverUri];
    }

    /** 
     * Registers a namespace URI into the server namespace table.
     * 
     * The same URI can only be registered once.
     *
     * Params: 
     *     uri = The namespace URI to register
     * 
     * Returns: 
     *     The index of the newly registered namespace
     * 
     * Throws: 
     *     DuaException if uri was already registered or if maximum namespace count was reached
     */
    int registerNamespace(string uri)
    out(ret; ret >= 2 && ret <= ushort.max)
    {
        enforce!DuaException(m_namespaces.length < ushort.max, "Maximum namespace count reached");

        ptrdiff_t found = m_namespaces.countUntil(uri);

        if (found != -1)
        {
            return cast(int) found;
        }
        else 
        {
            int ret = cast(int) m_namespaces.length;
            m_namespaces ~= uri;
            return ret;
        }
    }

    unittest
    {
        // Check the first URI is given index 2 (0 is UA and 1 is server)
        auto server = new Server("http//dua.org/");
        int idx = server.registerNamespace("http://spam.org/");
        assert (idx == 2);

        server.registerNamespace("http://egg.org/");

        // Check the same URI returns the same value
        idx = server.registerNamespace("http://spam.org/");
        assert (idx == 2);
    }

    /** 
     * Returns the index of the specified namespace URI.
     *
     * Params: 
     *     uri = The namespace URI to search for.
     * 
     * Returns: 
     *     The index of the namespace, or -1 if namespace could not be found.
     */
    int namespaceIndex(string uri) const nothrow
    {
        return cast(int) m_namespaces.countUntil(uri);
    }

    unittest 
    {
        auto server = new Server("http://dua.org/");
        int idx = server.registerNamespace("http://spam.org/");

        assert (server.namespaceIndex("http://opcfoundation.org/UA/") == 0);
        assert (server.namespaceIndex("http://dua.org/") == 1);
        assert (server.namespaceIndex("http://spam.org/") == idx);
    }

    /** 
     * Returns the URI associated to the specified namespace index
     * 
     * Params: 
     *     nsIdx = The namespace index
     * 
     * Returns:
     *     The URI associated to the index
     *
     * Throws: 
     *     DuaException if the specified namespace index is invalid.
     */
    string namespaceUri(int nsIdx) const 
    {
        enforce!DuaException(nsIdx >= 0 && nsIdx < m_namespaces.length, "Invalid namespace URI");
        return m_namespaces[nsIdx];
    }

    unittest 
    {
        auto server = new Server("http://dua.org/");
        assert ("http://dua.org/" == server.namespaceUri(1));
    }

    string applicationUri() const 
    {
        return m_applicationUri;
    }

private:
    string[] m_namespaces;
    string m_applicationUri;
    string m_productUri;
}