#import <Foundation/Foundation.h>

#if SG_DRIVER
// The persisted credential is rotated once when upgrading from a build that disclosed it.
NSString *SGDriverToken(void);
// Exactly one token header, fixed-length, case-sensitive credential comparison. Header names
// remain case-insensitive as HTTP requires; request bodies are never searched for credentials.
BOOL SGDriverRequestAuthorized(NSString *request, NSString *token);
#endif
