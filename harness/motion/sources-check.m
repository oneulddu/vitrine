// Production Canvas lookup/cache and protobuf codec, with controlled HTTP and file boundaries.
#import <UIKit/UIKit.h>
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/AnimatedArtwork/SGMotionTicket.h"
#import "Shared/AdBlock/Protobuf.h"
#import "Settings/SGModPage.h"
#import "Settings/SGSourcesPage.h"

#define CHECK(value) do { if (!(value)) { fprintf(stderr, "FAIL %d: %s\n", __LINE__, #value); exit(1); } } while (0)

BOOL SGFlag(NSString *key, BOOL fallback) { return fallback; }
NSString *SGL(NSString *key, NSString *english) { return english; }
void SGSpclientHeaders(void (^use)(NSDictionary *)) { use(@{@"Authorization": @"fixture"}); }
static BOOL holdFile;
static SGMotionTicket *fileTicket;
static NSUInteger fileRequests;
SGMotionTicket *SGMotionRequestFile(NSURL *remote, void (^done)(NSURL *)) {
    fileRequests++;
    SGMotionTicket *ticket = [SGMotionTicket new];
    fileTicket = ticket;
    if (!holdFile) dispatch_async(dispatch_get_main_queue(), ^{ if (!ticket.cancelled) done(remote); });
    return ticket;
}
SGMotionTicket *SGMotionRequestAlbumCover(NSString *artist, NSString *album, CGFloat pixels, void (^done)(NSURL *)) {
    CHECK(NO); // The fixture enables only Canvas.
    return nil;
}
// Settings-page linkage is not exercised by these source-walk checks.
@implementation SGSource
+ (instancetype)sourceWithKey:(NSString *)key name:(NSString *)name detail:(NSString *)detail { return nil; }
@end
SGModRow *SGPageRow(NSString *title, UIViewController *(^page)(void)) { return nil; }
SGModRow *SGWithSymbol(SGModRow *row, NSString *symbol) { return row; }
UIViewController *SGSourcesPageMake(NSString *title, NSString *note, NSArray *all,
                                   NSArray *(^order)(void), void (^setOrder)(NSArray *)) { return nil; }

static BOOL revised;
static NSUInteger heldRequests;
@interface CanvasProtocol : NSURLProtocol
@property (nonatomic, copy) NSString *uri;
- (void)finish;
@end
static CanvasProtocol *held;
@implementation CanvasProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    NSMutableData *body = [self.request.HTTPBody mutableCopy];
    if (!body) {
        body = [NSMutableData data];
        NSInputStream *stream = self.request.HTTPBodyStream;
        CHECK(stream);
        [stream open];
        uint8_t bytes[1024];
        NSInteger length;
        while ((length = [stream read:bytes maxLength:sizeof(bytes)]) > 0) [body appendBytes:bytes length:length];
        CHECK(length == 0);
        [stream close];
    }
    self.uri = SGPBText(SGPBFirst(SGPBParse(SGPBFirst(SGPBParse(body), 1).payload), 1));
    CHECK([self.uri hasPrefix:@"spotify:track:"]);
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.uri isEqual:@"spotify:track:held"]) {
            heldRequests++;
            held = self;
        } else [self finish];
    });
}
- (void)finish {
    NSData *data = [NSData data];
    if (revised || ![self.uri isEqual:@"spotify:track:negative"]) {
        NSString *url = revised ? @"https://fixture.invalid/second.mp4" : @"https://fixture.invalid/first.mp4";
        data = SGPBSerialize(@[SGPBBytes(1, SGPBSerialize(@[SGPBString(2, url), SGPBVarint(4, 1)]))]);
    }
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200
        HTTPVersion:@"HTTP/1.1" headerFields:nil];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

static void waitFor(BOOL (^ready)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!ready() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.001]];
    CHECK(ready());
}
static void ask(NSString *uri, void (^done)(NSURL *)) {
    SGMotionClipFor(uri, nil, @"Artist", @"Album", 720, ^(NSURL *file, NSString *source) {
        CHECK(file ? [source isEqual:@"canvas"] : source == nil);
        done(file);
    });
}
static NSURL *lookup(NSString *uri) {
    __block BOOL finished = NO;
    __block NSURL *answer;
    ask(uri, ^(NSURL *file) { CHECK(!finished); answer = file; finished = YES; });
    waitFor(^BOOL { return finished; });
    return answer;
}
int main(void) {
    @autoreleasepool {
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyMotionSources: @[@"canvas"]} forName:NSArgumentDomain];
        CHECK([NSURLProtocol registerClass:CanvasProtocol.class]);
        CHECK([lookup(@"spotify:track:positive").absoluteString isEqual:@"https://fixture.invalid/first.mp4"]);
        CHECK(lookup(@"spotify:track:negative") == nil);
        revised = YES;
        CHECK([lookup(@"spotify:track:positive").absoluteString isEqual:@"https://fixture.invalid/first.mp4"]);
        CHECK(lookup(@"spotify:track:negative") == nil);

        __block NSUInteger delivered = 0;
        void (^waiter)(NSURL *) = ^(NSURL *file) {
            CHECK([file.absoluteString isEqual:@"https://fixture.invalid/second.mp4"]);
            delivered++;
        };
        ask(@"spotify:track:held", waiter);
        ask(@"spotify:track:held", waiter);
        waitFor(^BOOL { return held != nil; });
        revised = NO;
        for (NSUInteger i = 0; i < 200; i++)
            CHECK(lookup([NSString stringWithFormat:@"spotify:track:fill-%lu", (unsigned long)i]) != nil);
        revised = YES;
        CHECK([lookup(@"spotify:track:fill-199").absoluteString isEqual:@"https://fixture.invalid/first.mp4"]);
        CHECK([lookup(@"spotify:track:positive").absoluteString isEqual:@"https://fixture.invalid/second.mp4"]);
        CHECK([lookup(@"spotify:track:negative").absoluteString isEqual:@"https://fixture.invalid/second.mp4"]);
        ask(@"spotify:track:held", waiter);
        CHECK(heldRequests == 1 && delivered == 0);
        [held finish];
        waitFor(^BOOL { return delivered == 3; });
        CHECK([lookup(@"spotify:track:held").absoluteString isEqual:@"https://fixture.invalid/second.mp4"]);
        CHECK(delivered == 3 && heldRequests == 1);
        holdFile = YES;
        SGMotionTicket *walk = SGMotionRequestClip(@"spotify:track:cancel", [NSURL URLWithString:@"https://fixture.invalid/held.mp4"],
            nil, nil, 720, ^(NSURL *file, NSString *source) { CHECK(NO); });
        [walk cancel];
        CHECK(fileTicket.cancelled);
        holdFile = NO;
        held = nil;
        // A cancelled metadata lookup must not start a file download when its reply arrives.
        // The cached Canvas answer still serves an unrelated consumer.
        NSUInteger before = fileRequests;
        walk = SGMotionRequestClip(@"spotify:track:cancel-metadata", nil, nil, nil, 720,
            ^(NSURL *file, NSString *source) { CHECK(NO); });
        [walk cancel];
        lookup(@"spotify:track:barrier");
        CHECK(fileRequests == before + 1);
        [NSURLProtocol unregisterClass:CanvasProtocol.class];
        puts("motion sources: positive/negative eviction and in-flight waiters passed");
        return 0;
    }
}
