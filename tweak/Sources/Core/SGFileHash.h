#import <Foundation/Foundation.h>

// SHA-256 in lowercase hex, reading one MiB at a time; nil when the file cannot be opened.
NSString *SGFileSHA256(NSURL *url);
