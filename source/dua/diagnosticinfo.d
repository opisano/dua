module dua.diagnosticinfo;

import dua.statuscode;

struct DiagnosticInfo
{
    int namespaceUri;
    int symbolicId;
    int locale;
    int localizedText;
    string additionalInfo;
    StatusCode innerStatusCode;
    DiagnosticInfo* innerDiagnosticInfo;
}