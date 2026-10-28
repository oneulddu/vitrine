// Real JSON transport and NetEase provider; only NSURLSession and the external keeper are doubles.
#import "Core/SGCore.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import <stdatomic.h>
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #c); exit(1); } } while (0)
static NSData *(^reply)(NSURLRequest *);
static NSInteger replyStatus = 200;
static NSError *replyError;
static NSUInteger decoded;

@interface TransportTask : NSObject
@property (nonatomic, copy) dispatch_block_t work;
- (void)resume;
@end
@implementation TransportTask
- (void)resume { dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), self.work); }
@end
@interface TransportSession : NSObject
+ (instancetype)sharedSession;
- (TransportTask *)dataTaskWithRequest:(NSURLRequest *)request
                    completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))done;
@end
@implementation TransportSession
+ (instancetype)sharedSession { return [self new]; }
- (TransportTask *)dataTaskWithRequest:(NSURLRequest *)request
                    completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))done {
    TransportTask *task = [TransportTask new];
    task.work = ^{
        NSData *body = reply(request);
        done(body, [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:replyStatus HTTPVersion:@"HTTP/1.1"
            headerFields:@{@"Retry-After": @"7"}], replyError);
    };
    return task;
}
@end
@interface TransportJSON : NSObject
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)options error:(NSError **)error;
+ (BOOL)isValidJSONObject:(id)value;
+ (NSData *)dataWithJSONObject:(id)value options:(NSJSONWritingOptions)options error:(NSError **)error;
@end
@implementation TransportJSON
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)options error:(NSError **)error {
    CHECK(!NSThread.isMainThread);
    decoded++;
    return [NSJSONSerialization JSONObjectWithData:data options:options error:error];
}
+ (BOOL)isValidJSONObject:(id)value { return [NSJSONSerialization isValidJSONObject:value]; }
+ (NSData *)dataWithJSONObject:(id)value options:(NSJSONWritingOptions)options error:(NSError **)error {
    return [NSJSONSerialization dataWithJSONObject:value options:options error:error];
}
@end
static const NSTimeInterval kTimeout = 6;
#define NSURLSession TransportSession
#define NSJSONSerialization TransportJSON
#import "transport.inc"
#undef NSJSONSerialization
// NetEase has its own 3-second request policy.
#define kTimeout kNetEaseTimeout
#import "Shared/LyricsSources/NetEase.m"
#undef kTimeout
#undef NSURLSession
@implementation SGLyricsResult
@end
@implementation SGLyricsQuery
@end
void SGLyricsPageLines(NSArray *lines, NSArray **starts, NSArray **texts) {
    NSMutableArray *at = [NSMutableArray array], *words = [NSMutableArray array];
    for (SGKaraokeLine *line in lines) { [at addObject:@(line.start)]; [words addObject:SGKaraokeLineText(line)]; }
    *starts = at; *texts = words;
}
void SGLyricsSourceRequest(NSURL *url, NSDictionary *headers, NSData *body, void (^done)(NSData *, NSInteger)) {
    CHECK(NO); // These cases never use LRCLIB's bounded source request.
}
static void waitFor(BOOL *finished) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!*finished && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    CHECK(*finished);
}
static NSData *json(id value) { return [NSJSONSerialization dataWithJSONObject:value options:0 error:nil]; }
int main(void) {
    @autoreleasepool {
        NSURL *url = [NSURL URLWithString:@"https://fixture.invalid/lyrics"];
        NSString *large = [@"a" stringByPaddingToLength:500000 withString:@"a" startingAtIndex:0];
        reply = ^NSData *(NSURLRequest *request) { return json(@{@"text": large, @"candidate": @17}); };
        __block BOOL finished = NO;
        SGLyricsGetJSONTransform(url, nil, ^id(id root) {
            CHECK(!NSThread.isMainThread);
            CHECK([root[@"text"] length] == 500000);
            return root[@"candidate"];
        }, ^(id value) { CHECK(NSThread.isMainThread && [value isEqual:@17]); finished = YES; });
        waitFor(&finished);
        CHECK(decoded == 1);
        finished = NO;
        SGLyricsPostJSON(url, nil, @{@"ask": @YES}, ^(id root) {
            CHECK(NSThread.isMainThread && [root[@"candidate"] isEqual:@17]); finished = YES;
        });
        waitFor(&finished);
        replyStatus = 429;
        finished = NO;
        SGLyricsGetJSONReply(url, nil, ^(id root, NSHTTPURLResponse *response) {
            CHECK(NSThread.isMainThread && response.statusCode == 429);
            CHECK([response.allHeaderFields[@"Retry-After"] isEqual:@"7"] && [root[@"candidate"] isEqual:@17]);
            finished = YES;
        });
        waitFor(&finished);
        CHECK(atomic_load(&sg_failures) == 1);
        replyStatus = 200;
        reply = ^NSData *(NSURLRequest *request) { return [@"{broken" dataUsingEncoding:NSUTF8StringEncoding]; };
        finished = NO;
        SGLyricsGetJSON(url, nil, ^(id root) { CHECK(NSThread.isMainThread && !root); finished = YES; });
        waitFor(&finished);
        finished = NO;
        SGLyricsPostJSON(url, nil, [NSObject new], ^(id root) { CHECK(NSThread.isMainThread && !root); finished = YES; });
        waitFor(&finished);
        finished = NO;
        SGLyricsGetText(url, ^(NSString *text) { CHECK(NSThread.isMainThread && [text isEqual:@"{broken"]); finished = YES; });
        waitFor(&finished);
        reply = ^NSData *(NSURLRequest *request) {
            CHECK(request.timeoutInterval == 3);
            if ([request.URL.path isEqual:@"/api/search/get"]) return json(@{@"result": @{@"songs": @[
                @{@"id": @1, @"name": @"Different", @"duration": @200000, @"artists": @[@{@"name": @"Singer"}]},
                @{@"id": @2, @"name": @"Fixture (Live)", @"duration": @200000, @"artists": @[@{@"name": @"Singer"}]},
                @{@"id": @3, @"name": @42, @"duration": @200000, @"artists": @[@{@"name": @"Singer"}]},
                @{@"id": @4, @"name": @" Fixture! ", @"duration": @200000, @"artists": @[@{@"name": @"Singer"}]}
            ]}});
            CHECK([request.URL.query containsString:@"id=4"]);
            return json(@{@"yrc": @{@"lyric": @"[1234,1000](1234,200,0)Hello"}});
        };
        SGLyricsQuery *query = [SGLyricsQuery new];
        query.title = @"Fixture"; query.artist = @"Singer"; query.seconds = 200;
        finished = NO;
        SGNetEaseAsk(query, ^(SGLyricsResult *result) {
            CHECK(NSThread.isMainThread && result.wordTimed);
            CHECK(result.karaokeLines[0].words[0].start == 1234 && result.karaokeLines[0].words[0].end == 1434);
            finished = YES;
        });
        waitFor(&finished);
        puts("Shared transport: worker decode/transform, main delivery and NetEase title checks passed");
    }
    return 0;
}
