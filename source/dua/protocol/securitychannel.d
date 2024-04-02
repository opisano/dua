module dua.protocol.securitychannel;


import dua.protocol.session;
import std.datetime;

alias bstring = immutable(ubyte)[];


/** 
 * The type of SecurityToken request
 */
enum SecurityTokenRequestType
{
    /// creates a new SecurityToken for a new SecureChannel.
    Issue = 0,

    /// creates a new SecurityToken for an existing SecureChannel.
    Renew = 1
}


/** 
 * The MessageSecurityMode is an enumeration that specifies what security should be applied to messages exchanges 
 * during a Session.
 */
enum MessageSecurityMode
{
    ///  The MessageSecurityMode is invalid. 
    Invalid = 0,

    ///  No security is applied. 
    None = 1,

    ///  All messages are signed but not encrypted. 
    Sign = 2,

    ///  All messages are signed and encrypted. 
    SignAndEncrypt = 3
}


/** 
 * OpenSecureChannel Service Parameters
 * 
 */
struct OpenSecureChannelParameters(DataType)
{
    ///  Common request parameters. The authenticationToken is always null. 
    RequestHeader requestHeader;

    ///  A Certificate that identifies the Client. 
    ApplicationInstanceCertificate clientCertificate;

    ///  The type of SecurityToken request
    SecurityTokenRequestType requestType;

    /// The identifier for the SecureChannel that the new token should belong to
    DataType secureChannelId;

    /// The type of security to apply to the messages
    MessageSecurityMode securityMode;

    /// The URI for SecurityPolicy to use when securing messages sent over the SecureChannel. 
    string securityPolicyUri;
    
    /// A random number that shall not be used in any other request. 
    bstring clientNonce;

    /// The requested lifetime, in milliseconds, for the new SecurityToken. 
    Duration requestedLifetime;
}