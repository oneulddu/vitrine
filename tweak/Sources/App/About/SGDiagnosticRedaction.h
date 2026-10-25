#import <Foundation/Foundation.h>

// Redacts install-private names and stored string values, including values spanning lines.
NSString *SGRedactDiagnostics(NSString *text, NSDictionary<NSString *, id> *preferences);
