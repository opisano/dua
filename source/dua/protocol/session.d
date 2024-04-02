module dua.protocol.session;

import dua.node;
import std.datetime;

/** 
 * Common parameters for all requests submitted on a Session. 
 */
struct RequestHeader 
{
    /// The secret Session identifier used to verify that the request is associated with the Session.
    NodeId authenticationToken;

    /// The time the Client sent the request.
    SysTime timestamp;

    /// A requestHandle associated with the request. 
    uint requestHandle;

    /**  
     * A bit mask that identifies the types of vendor-specific diagnostics to be returned in diagnosticInfo 
     * response parameters. 
     */ 
    uint returnDiagnostics;

    /// An identifier that identifies the Client’s security audit log entry associated with this request.
    string auditEntryId;

    /** 
     * This timeout in milliseconds is used in the Client side Communication Stack to set the timeout 
     * on a per-call base. 
     */ 
    uint timeoutHint;

    ///  Reserved for future use. 
    uint additionalHeader;
}
