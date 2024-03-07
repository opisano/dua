module dua.except;

class SystemException : Exception 
{
    this(string msg, 
         string file = __FILE__, 
         size_t line = __LINE__, 
         Throwable nextInChain = null) pure nothrow @nogc @safe
    {
        super(msg, file, line, nextInChain);
    }
}

class DuaException : Exception
{
    this(string msg, 
         string file = __FILE__, 
         size_t line = __LINE__, 
         Throwable nextInChain = null) pure nothrow @nogc @safe
    {
        super(msg, file, line, nextInChain);
    }
}

class DuaBadDecodingException : DuaException
{
    this(string msg, 
         string file = __FILE__, 
         size_t line = __LINE__, 
         Throwable nextInChain = null) pure nothrow @nogc @safe
    {
        super(msg, file, line, nextInChain);
    }
}

class DuaBadEncodingException : Exception
{
    this(string msg, 
         string file = __FILE__, 
         size_t line = __LINE__, 
         Throwable nextInChain = null) pure nothrow @nogc @safe
    {
        super(msg, file, line, nextInChain);
    }
}

