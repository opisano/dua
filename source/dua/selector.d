/** 
 * This module implements trusted and portable select()-like functionality. 
 * 
 * The goal of this module is to have a simple abstraction over the facility 
 * provided by the operating system to detect incoming data over non-blocking 
 * sockets or file descriptors.
 * 
 * In this regard, a Selector interface is declared here, which is to be 
 * implemented by various classes depending on the operating system.
 */
module dua.selector;

import core.stdc.errno;
import core.stdc.string;

import core.sys.posix.poll;
import core.sys.posix.unistd;
import dua.except;
import std.algorithm;
import std.exception;
import std.string;

@safe:

enum Mask 
{
    /// Data was read
    Input = 1,
    /// An error occured
    Error = 2,
    /// Hang up happened on the file descriptor
    HangUp = 4
}

/** 
 * Alias to the type of delegate used to process incoming data 
 *
 * - fd is the file descriptor from which data was read.
 * - mask is a bitmask which can be a combination of Mask values or'ed together.
 * - readBytes is the data read (if any).
 */
alias SelectorDelegate = void delegate(int fd, uint mask, scope const(ubyte)[] readBytes);

/** 
 * Interface for a selector.  
 */ 
interface Selector
{
    /** 
     * Add a file descriptor to the selector
     *
     * Params: 
     *     fd = File descriptor to add 
     *     deleg = Delegate to call when data arrives 
     */
    void add(int fd, SelectorDelegate deleg);

    /** 
     * Remove a file descriptor from the selector
     * 
     * Params: 
     *     fd = File descriptor to remove
     */
    void remove(int fd);

    /** 
     * Performs actual selection, calling the delegates for registered 
     * file descriptors.
     * 
     * Params: 
     *    timeoutMs = Maximum timeout (in milliseconds) to wait before returning.
     */
    void select(int timeoutMs);
}

/** 
 * Poll-based selector implementation. 
 * 
 * This implementation is slow for large file descriptor count, use for 
 * default implementation where epoll is not available.
 */
final class PollSelector : Selector
{
    enum INITIAL_SIZE = 16;

    this() scope
    {
        m_fds = new pollfd[INITIAL_SIZE];
    }

    override void add(int fd, SelectorDelegate deleg) scope
    {
        if (m_monitorCount == m_fds.length)
        {
            grow();
        }

        m_fds[m_monitorCount].fd = fd;
        m_fds[m_monitorCount].events = POLLIN;
        m_monitorCount++;
        m_delegates[fd] = deleg;
    }

    unittest 
    {
        scope sel = new PollSelector;
        assert (sel.m_monitorCount == 0);

        for (size_t i = 0; i < 50; ++i)
        {
            sel.add(0, null);
        }

        assert (sel.m_monitorCount == 50);
        assert (sel.m_fds.length > 50);
    }

    override void remove(int fd) scope
    {
        // search for fd
        auto idx = m_fds.countUntil!(pfd => pfd.fd == fd);

        // if found
        if (idx >= 0)
        {
            m_fds = m_fds.remove(idx);
            m_monitorCount--;
            m_delegates.remove(fd);
        }        
    }

    override void select(int timeoutMs) scope @trusted
    {
        int nbEvents = poll(&m_fds[0], m_monitorCount, timeoutMs);

        if (nbEvents < 0)
        {
            string msg = errno.strerror.fromStringz.dup;
            throw new SystemException("Failed to add file descriptor to epoll: %s".format(msg));
        }

        if (nbEvents > 0)
        {
            int count = 0; // number processed so far...

            foreach (ref const pfd; m_fds[0 .. m_monitorCount])
            {
                // if every event has been processed, leave
                if (count == nbEvents)
                {
                    break;
                }

                // Check if current element is concerned
                int happened = pfd.revents & POLLIN;
                if (happened)
                {
                    count++; // mark as processed

                    SelectorDelegate* p = (pfd.fd in m_delegates);
                    if (p !is null)
                    {
                        ubyte[4096] buffer = void;
                        ssize_t bytesRead = read(pfd.fd, buffer.ptr, buffer.length);
                        
                        // call delegate
                        (*p)(pfd.fd, cast(uint)Mask.Input, buffer[0 .. bytesRead]);
                    }
                }
            }
        }
    }

private:

    /** 
     * Make internal buffer grow.
     */
    void grow() scope
    {
        // calculate new size 
        size_t newSize = cast(size_t) (m_fds.length * 1.5);
        // allocate new array
        auto temp = new pollfd[newSize];
        // copy existing fds to new array
        temp[0 .. m_monitorCount] = m_fds[0 .. m_monitorCount];
        // make m_fds point to new array
        m_fds = temp;
    }

    /// Stores file descriptors
    pollfd[] m_fds;

    /// int -> SelectorDelegate association
    SelectorDelegate[int] m_delegates;

    /// Number for file descriptors currently monitored
    size_t m_monitorCount;
}

unittest
{
    int[2] pipefd;
    bool success = false;

    // function to be called when bytes are read
    void onBytesRead(int fd, uint mask, scope const(ubyte)[] bytesRead)
    {
        success = (fd == pipefd[0]) && (bytesRead == "MEUH");
    }

    // Create a pipe 
    immutable int error = pipe(pipefd);
    assert (error == 0);

    scope (exit)
    {
        close(pipefd[0]);
        close(pipefd[1]);
    }

    scope sel = new PollSelector;
    sel.add(pipefd[0], &onBytesRead);

    ( () @trusted => write(pipefd[1], &"MEUH"[0], 4) )();
    sel.select(100);

    assert (success);
}

version (linux)
{

import core.sys.linux.epoll;

/** 
 * Epoll-based selector implementation. Much faster than PollSelector, but 
 * only available on linux.
 * 
 */
final class EpollSelector : Selector
{
    enum INITIAL_SIZE = 16;

    this() scope @trusted
    {
        m_epollFd = epoll_create(1);

        if (m_epollFd < 0) // Error occured
        {
            string msg = errno.strerror.fromStringz.dup;
            throw new SystemException("Failed to add file descriptor to epoll: %s".format(msg));
        }

        m_events = new epoll_event[INITIAL_SIZE];
    }

    ~this()
    {
        close(m_epollFd);
    }

    override void add(int fd, SelectorDelegate deleg) scope @trusted
    {
        // Add file descriptor to epoll
        epoll_event event;
        event.events = EPOLLIN | EPOLLERR | EPOLLHUP;
        event.data.fd = fd;

        int error = epoll_ctl(m_epollFd, EPOLL_CTL_ADD, fd, &event);

        if (error)
        {
            string msg = errno.strerror.fromStringz.dup;
            throw new SystemException("Failed to add file descriptor to epoll: %s".format(msg));
        }
        m_delegates[fd] = deleg;

        // check if event array needs to grow
        m_monitorCount++;
        if (m_monitorCount > m_events.length)
        {
            size_t newSize = cast(size_t)(m_events.length * 1.5);
            m_events = new epoll_event[newSize];
        }
    }

    unittest 
    {
        scope sel = new EpollSelector;

        // adding standard error is fine
        sel.add(0, null);

        // adding invalid file descriptor is not
        assertThrown!SystemException(sel.add(-1, null));
    }

    override void remove(int fd) scope @trusted
    {
        // Remove file descriptor from epoll 
        epoll_event event;
        event.events = EPOLLIN | EPOLLERR | EPOLLHUP;
        event.data.fd = fd;

        int error = epoll_ctl(m_epollFd, EPOLL_CTL_DEL, fd, &event);

        if (error)
        {
            string msg = errno.strerror.fromStringz.dup;
            throw new SystemException("Failed to remove file descriptor from epoll: %s".format(msg));
        }

        m_delegates.remove(fd);

        // check if event array needs to shrink
        m_monitorCount--;
        if ((m_monitorCount < m_events.length / 2) 
                && (m_events.length > INITIAL_SIZE))
        {
            size_t newSize = max(cast(size_t)(m_events.length / 1.5), INITIAL_SIZE);
            m_events = new epoll_event[newSize];
        }
    }

    unittest 
    {
        scope sel = new EpollSelector;

        // adding standard error is fine
        sel.add(0, null);

        sel.remove(0);

        // removing a non-existent fd throws
        assertThrown!SystemException(sel.remove(0));
    }

    override void select(int timeoutMs) scope @trusted
    {
        immutable int fdNbs = epoll_wait(m_epollFd, m_events.ptr, cast(int)m_events.length, timeoutMs);

        if (fdNbs < 0) // Error 
        {
            string msg = errno.strerror.fromStringz.dup;
            throw new SystemException("Failed to wait from epoll: %s".format(msg));
        }
        else 
        {
            // for each event
            for (int i = 0; i < fdNbs; ++i)
            {
                // get fd and mask values
                int fd = m_events[i].data.fd;
                uint mask = epollToMask(m_events[i].events);

                // get the delegate associated with fd 
                SelectorDelegate* p = (fd in m_delegates);
                if (p !is null)
                {
                    ubyte[4096] buffer = void;
                    ssize_t bytesRead = 0;

                    // if need to read data
                    if (mask & Mask.Input)
                    {
                        bytesRead = read(fd, buffer.ptr, buffer.length);
                    }

                    // call delegate
                    (*p)(fd, mask, buffer[0 .. bytesRead]);
                }
            }
        }
    }

    unittest
    {
        int[2] pipefd;
        bool success = false;

        // function to be called when bytes are read
        void onBytesRead(int fd, uint mask, scope const(ubyte)[] bytesRead)
        {
            success = (fd == pipefd[0]) && (bytesRead == "MEUH");
        }

        // Create a pipe 
        immutable int error = pipe(pipefd);
        assert (error == 0);

        scope (exit)
        {
            close(pipefd[0]);
            close(pipefd[1]);
        }

        scope sel = new EpollSelector;
        sel.add(pipefd[0], &onBytesRead);

        ( () @trusted => write(pipefd[1], &"MEUH"[0], 4) )();
        sel.select(100);

        assert (success);
    }

private:

    static uint epollToMask(uint epollMask) pure nothrow @nogc
    {
        uint ret;

        ret |= (epollMask & EPOLLIN) ? Mask.Input : 0;
        ret |= (epollMask & EPOLLERR) ? Mask.Error : 0;
        ret |= (epollMask & EPOLLHUP) ? Mask.HangUp : 0;

        return ret;
    }

    unittest 
    {
        uint input = EPOLLIN | EPOLLERR | EPOLLHUP;
        uint output = EpollSelector.epollToMask(input);

        assert (output & Mask.Input);
        assert (output & Mask.Error);
        assert (output & Mask.HangUp);
    }

    /// int -> SelectorDelegate association
    SelectorDelegate[int] m_delegates;

    /// stores events
    epoll_event[] m_events;

    /// Number for file descriptors currently monitored
    size_t m_monitorCount;

    /// epoll file descriptor
    int m_epollFd;
}

}