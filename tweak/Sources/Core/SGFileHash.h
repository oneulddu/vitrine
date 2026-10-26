#import <Foundation/Foundation.h>

// SHA-256 of the supplied bytes in lowercase hex; nil data hashes as empty data.
NSString *SGDataSHA256(NSData *data);

// SHA-256 in lowercase hex, reading one MiB at a time; nil when the file cannot be opened.
NSString *SGFileSHA256(NSURL *url);
