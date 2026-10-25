#import "Shared/LocalFiles/LocalLyrics.h"

// Synchronous fixture setup around the asynchronous production import; callbacks still run on main.
static NSString *importLRC(NSURL *url, NSString *uri, NSError **error) {
    __block BOOL done = NO;
    __block NSString *name;
    __block NSError *failure;
    SGImportLRC(url, uri, ^(NSString *imported, NSError *reason) {
        if (!NSThread.isMainThread) { fprintf(stderr, "LRC completion is not on main\n"); exit(1); }
        name = imported; failure = reason; done = YES;
    });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!done && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    if (!done) { fprintf(stderr, "LRC import timed out\n"); exit(1); }
    if (error) *error = failure;
    return name;
}
