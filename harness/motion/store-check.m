// Production motion store. Filesystem boundaries reject main-thread work; no network is used.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"

#define CHECK(value) do { if (!(value)) { fprintf(stderr, "FAIL %d: %s\n", __LINE__, #value); exit(1); } } while (0)
static NSURL *root;
static BOOL watch;
BOOL SGFlag(NSString *key, BOOL fallback) { return fallback; }
static void offMain(NSString *path) { if (watch && [path hasPrefix:root.path]) CHECK(!NSThread.isMainThread); }

@interface NSFileManager (StoreCheck)
- (NSArray *)testURLsForDirectory:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)domains;
- (BOOL)testExists:(NSString *)path;
- (BOOL)testCreate:(NSURL *)url withIntermediateDirectories:(BOOL)parents attributes:(NSDictionary *)attributes error:(NSError **)error;
- (NSArray *)testContents:(NSURL *)url includingPropertiesForKeys:(NSArray *)keys options:(NSDirectoryEnumerationOptions)options error:(NSError **)error;
@end
@implementation NSFileManager (StoreCheck)
- (NSArray *)testURLsForDirectory:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)domains {
    return directory == NSCachesDirectory ? @[root] : [self testURLsForDirectory:directory inDomains:domains];
}
- (BOOL)testExists:(NSString *)path { offMain(path); return [self testExists:path]; }
- (BOOL)testCreate:(NSURL *)url withIntermediateDirectories:(BOOL)parents attributes:(NSDictionary *)attributes error:(NSError **)error {
    offMain(url.path); return [self testCreate:url withIntermediateDirectories:parents attributes:attributes error:error];
}
- (NSArray *)testContents:(NSURL *)url includingPropertiesForKeys:(NSArray *)keys options:(NSDirectoryEnumerationOptions)options error:(NSError **)error {
    offMain(url.path); return [self testContents:url includingPropertiesForKeys:keys options:options error:error];
}
@end
static void exchange(SEL original, SEL replacement) {
    method_exchangeImplementations(class_getInstanceMethod(NSFileManager.class, original),
                                   class_getInstanceMethod(NSFileManager.class, replacement));
}
static void waitFor(BOOL (^ready)(void)) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!ready() && until.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.001]];
    CHECK(ready());
}
static void writeFile(NSURL *file) {
    __block BOOL done = NO;
    SGMotionMakeFile(file, ^BOOL {
        CHECK(!NSThread.isMainThread);
        return [@"clip" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }, ^(BOOL ok) { CHECK(ok); dispatch_async(dispatch_get_main_queue(), ^{ done = YES; }); });
    waitFor(^BOOL { return done; });
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        CHECK(argc == 2);
        root = [NSURL fileURLWithPath:@(argv[1]) isDirectory:YES];
        exchange(@selector(URLsForDirectory:inDomains:), @selector(testURLsForDirectory:inDomains:));
        exchange(@selector(fileExistsAtPath:), @selector(testExists:));
        exchange(@selector(createDirectoryAtURL:withIntermediateDirectories:attributes:error:), @selector(testCreate:withIntermediateDirectories:attributes:error:));
        exchange(@selector(contentsOfDirectoryAtURL:includingPropertiesForKeys:options:error:), @selector(testContents:includingPropertiesForKeys:options:error:));
        watch = YES;
        NSURL *made = SGMotionMadeFile(@"a generated clip");
        CHECK(made.lastPathComponent.length == 44);
        watch = NO;
        CHECK(![NSFileManager.defaultManager fileExistsAtPath:root.path]);
        watch = YES;
        writeFile(made);
        for (NSUInteger i = 0; i < 41; i++) {
            @autoreleasepool { writeFile(SGMotionMadeFile([NSString stringWithFormat:@"clip-%lu", (unsigned long)i])); }
        }
        watch = NO;
        CHECK([NSFileManager.defaultManager contentsOfDirectoryAtURL:made.URLByDeletingLastPathComponent
            includingPropertiesForKeys:nil options:0 error:nil].count == 40);
        // Seed the documented address-hashed cache, then ask through the public remote entrypoint.
        NSURL *remote = [NSURL URLWithString:@"https://fixture.invalid/clip.mp4"];
        NSData *address = [remote.absoluteString dataUsingEncoding:NSUTF8StringEncoding];
        unsigned char digest[CC_SHA1_DIGEST_LENGTH]; CC_SHA1(address.bytes, (CC_LONG)address.length, digest);
        NSMutableString *name = [NSMutableString string];
        for (NSUInteger i = 0; i < sizeof(digest); i++) [name appendFormat:@"%02x", digest[i]];
        NSURL *cached = [made.URLByDeletingLastPathComponent URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"mp4"]];
        CHECK([@"clip" writeToURL:cached atomically:YES encoding:NSUTF8StringEncoding error:nil]);
        CHECK([NSFileManager.defaultManager setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSince1970:1]}
            ofItemAtPath:cached.path error:nil]);
        watch = YES;
        __block NSUInteger replies = 0;
        for (NSUInteger i = 0; i < 2; i++) SGMotionFile(remote, ^(NSURL *file) {
            CHECK(NSThread.isMainThread && [file isEqual:cached]);
            CHECK([[NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:nil] isEqual:@"clip"]);
            NSDate *modified = [NSFileManager.defaultManager attributesOfItemAtPath:file.path error:nil][NSFileModificationDate];
            CHECK([modified timeIntervalSince1970] > 1);
            replies++;
        });
        // Main stays held: the hit has queued its delivery, then more than one cache's
        // worth of writes trims before the consumer can even receive the handoff.
        dispatch_semaphore_t written = dispatch_semaphore_create(0);
        for (NSUInteger i = 0; i < 41; i++) {
            @autoreleasepool {
                NSURL *next = SGMotionMadeFile([NSString stringWithFormat:@"after-hit-%lu", (unsigned long)i]);
                SGMotionMakeFile(next, ^BOOL {
                    return [@"later" writeToURL:next atomically:YES encoding:NSUTF8StringEncoding error:nil];
                }, ^(BOOL ok) { CHECK(ok); if (i == 40) dispatch_semaphore_signal(written); });
            }
        }
        CHECK(dispatch_semaphore_wait(written, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
        waitFor(^BOOL { return replies == 2; });
        watch = NO;
        CHECK([NSFileManager.defaultManager removeItemAtURL:root error:nil]);
        puts("motion store: pure names, background creation/trim and asynchronous cached lookup passed");
        return 0;
    }
}
