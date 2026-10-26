#import "SGFileHash.h"
#import <CommonCrypto/CommonDigest.h>

NSString *SGFileSHA256(NSURL *url) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:nil];
    if (!handle) return nil;
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    for (;;) {
        @autoreleasepool {
            NSData *chunk = [handle readDataUpToLength:1 << 20 error:nil];
            if (!chunk.length) break;
            CC_SHA256_Update(&context, chunk.bytes, (CC_LONG)chunk.length);
        }
    }
    [handle closeFile];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *hex = [NSMutableString stringWithCapacity:2 * CC_SHA256_DIGEST_LENGTH];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}
