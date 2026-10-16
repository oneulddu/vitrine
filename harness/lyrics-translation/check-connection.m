// Included by check.m; scripted service replies, then production one-shot transport via NSURLProtocol.
#import "Shared/LyricsTranslation/ConnectionTest.h"
#import <objc/runtime.h>
NSURLSessionDataTask *SGLyricsTranslationRealSendOnce(NSURLRequest *, void (^)(NSData *, NSInteger, NSError *));
@interface SGConnectionFakeTask : NSObject
@property BOOL cancelled;
@end
@implementation SGConnectionFakeTask
- (void)cancel { self.cancelled = YES; }
@end
static NSUInteger connectionSends;
static NSURLRequest *connectionRequest;
static SGConnectionFakeTask *connectionTask;
static void (^connectionReply)(NSData *, NSInteger, NSError *);
NSURLSessionDataTask *SGLyricsTranslationSendOnce(NSURLRequest *request, void (^done)(NSData *, NSInteger, NSError *)) {
    connectionSends++; connectionRequest = request; connectionReply = [done copy];
    connectionTask = [SGConnectionFakeTask new];
    return (id)connectionTask;
}
static NSData *connectionData(NSString *text) {
    NSData *array = [NSJSONSerialization dataWithJSONObject:@[text] options:0 error:nil];
    return [NSJSONSerialization dataWithJSONObject:chatReply([[NSString alloc] initWithData:array encoding:NSUTF8StringEncoding]) options:0 error:nil];
}
static void connectionDrain(void) {
    __block BOOL drained = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; });
    waitFor(^BOOL { return drained; });
}
static void connectionConfigure(void) {
    [NSUserDefaults.standardUserDefaults setObject:@"http://100.97.8.81:10100/v1" forKey:SGKeyLyricsOpenAIBaseURL];
    [NSUserDefaults.standardUserDefaults setObject:@"offline-model" forKey:SGKeyLyricsOpenAIModel];
    testKeys = [NSSet setWithObject:@"Vitrine.OpenAI"];
    openAIKeys = [@{@"100.97.8.81": [@"connection-fixture-key" dataUsingEncoding:NSUTF8StringEncoding],
                    @"other.invalid": [@"other-fixture-key" dataUsingEncoding:NSUTF8StringEncoding]} mutableCopy];
    keyReadFailure = keyWriteFailure = keyDeleteFailure = 0;
    testLanguage = @"ko";
}
static NSString *connectionResult(NSData *data, NSInteger status, NSError *error, BOOL success) {
    __block NSUInteger calls = 0;
    __block NSString *problem;
    NSUInteger before = connectionSends;
    SGTranslationConnectionTest *test = SGTestOpenAITranslation(^(NSString *translation, NSString *failure) {
        CHECK(NSThread.isMainThread && ++calls == 1);
        CHECK(success ? (translation.length && !failure) : (!translation && failure.length));
        CHECK(![failure containsString:@"connection-fixture-key"] && ![failure containsString:@"100.97.8.81"]);
        problem = failure;
    });
    CHECK(test && connectionSends == before + 1);
    connectionReply(data, status, error);
    connectionReply(data, status, error); // Deliberately hostile duplicate transport callback.
    connectionDrain(); CHECK(calls == 1);
    connectionReply = nil;
    return problem;
}

static NSInteger connectionHTTPStatus;
static NSData *connectionHTTPData;
static BOOL connectionHTTPHold;
static NSUInteger connectionHTTPStarts;
@interface SGConnectionProtocol : NSURLProtocol
@end
@implementation SGConnectionProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [request.URL.host isEqual:@"127.0.0.1"] && request.URL.port.integerValue == 1; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    dispatch_async(dispatch_get_main_queue(), ^{
    connectionHTTPStarts++;
    CHECK(self.request.timeoutInterval == 20 && !self.request.HTTPShouldHandleCookies);
    if (connectionHTTPHold) return;
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:connectionHTTPStatus HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:connectionHTTPData];
    [self.client URLProtocolDidFinishLoading:self];
    });
}
- (void)stopLoading {}
@end
// Ephemeral sessions do not inherit globally registered protocols on every OS.
// Inject only the protocol list; production owns every transport policy and delegate.
@interface NSURLSessionConfiguration (SGConnectionFixture)
+ (NSURLSessionConfiguration *)sg_connectionEphemeral;
@end
@implementation NSURLSessionConfiguration (SGConnectionFixture)
+ (NSURLSessionConfiguration *)sg_connectionEphemeral {
    NSURLSessionConfiguration *config = [self sg_connectionEphemeral];
    config.protocolClasses = @[SGConnectionProtocol.class];
    return config;
}
@end
// Test the exact production redirect delegate separately: NSURLProtocol redirects are not portable.
@interface SGLyricsTranslationRequest : NSObject <NSURLSessionDataDelegate>
@end
static void checkConnectionTransport(void) {
    Method original = class_getClassMethod(NSURLSessionConfiguration.class, @selector(ephemeralSessionConfiguration));
    Method fixture = class_getClassMethod(NSURLSessionConfiguration.class, @selector(sg_connectionEphemeral));
    method_exchangeImplementations(original, fixture);
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:1/connection-fixture"]];
    for (NSNumber *code in @[@200, @429, @503]) {
        connectionHTTPStatus = code.integerValue; connectionHTTPData = [@"fixture" dataUsingEncoding:NSUTF8StringEncoding];
        NSUInteger before = connectionHTTPStarts;
        __block NSUInteger calls = 0;
        SGLyricsTranslationRealSendOnce(request, ^(NSData *data, NSInteger status, NSError *error) {
            CHECK(NSThread.isMainThread && ++calls == 1 && !error && status == code.integerValue);
            CHECK([data isEqual:connectionHTTPData]);
        });
        waitFor(^BOOL { return calls > 0; });
        CHECK(connectionHTTPStarts == before + 1);
    }
    // Unknown-length payloads exercise accumulation bounds, not merely Content-Length rejection.
    for (NSNumber *size in @[@(512 * 1024), @(512 * 1024 + 1)]) {
        connectionHTTPStatus = 200; connectionHTTPData = [NSMutableData dataWithLength:size.unsignedIntegerValue];
        __block NSUInteger calls = 0;
        SGLyricsTranslationRealSendOnce(request, ^(NSData *data, NSInteger status, NSError *error) {
            CHECK(NSThread.isMainThread && ++calls == 1);
            CHECK(size.unsignedIntegerValue == 512 * 1024 ? (!error && data.length == 512 * 1024) : (error && !data));
        });
        waitFor(^BOOL { return calls > 0; });
    }
    connectionHTTPHold = YES;
    NSUInteger before = connectionHTTPStarts;
    __block NSUInteger calls = 0;
    NSURLSessionDataTask *task = SGLyricsTranslationRealSendOnce(request, ^(NSData *data, NSInteger status, NSError *error) {
        CHECK(NSThread.isMainThread && ++calls == 1 && !data && error.code == NSURLErrorCancelled);
    });
    waitFor(^BOOL { return connectionHTTPStarts > before; });
    [task cancel]; waitFor(^BOOL { return calls == 1; });
    connectionHTTPHold = NO;
    SGLyricsTranslationRequest *receiver = [SGLyricsTranslationRequest new];
    __block BOOL refused = NO;
    [receiver URLSession:NSURLSession.sharedSession task:task willPerformHTTPRedirection:[[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:302 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Location": @"https://other.invalid/"}] newRequest:request completionHandler:^(NSURLRequest *redirect) { CHECK(!redirect); refused = YES; }];
    CHECK(refused);
    method_exchangeImplementations(original, fixture);
    puts("Connection transport: real SendOnce, 20s request, 429/503 no retry, cancel, 512 KiB boundary; direct redirect delegate passed");
}
static void checkConnection(void) {
    NSArray *settings = @[SGKeyLyricsOpenAIBaseURL, SGKeyLyricsOpenAIModel];
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    for (NSString *key in settings) saved[key] = [NSUserDefaults.standardUserDefaults objectForKey:key] ?: NSNull.null;
    NSSet *savedKeys = testKeys; NSMutableDictionary *savedOpenAIKeys = openAIKeys;
    NSString *savedLanguage = testLanguage;
    connectionConfigure();
    [openAIKeys removeAllObjects];
    NSUInteger before = connectionSends;
    __block NSUInteger calls = 0;
    SGTranslationConnectionTest *test = SGTestOpenAITranslation(^(NSString *answer, NSString *error) { CHECK(NSThread.isMainThread && !answer && error.length); calls++; });
    connectionDrain(); CHECK(test && calls == 1 && connectionSends == before);
    connectionConfigure();
    connectionResult(connectionData(@"하늘은 파랗다."), 200, nil, YES);
    CHECK([connectionRequest.URL.absoluteString isEqual:@"http://100.97.8.81:10100/v1/chat/completions"]);
    CHECK([[connectionRequest valueForHTTPHeaderField:@"Authorization"] isEqual:@"Bearer connection-fixture-key"]);
    CHECK([connectionRequest.HTTPMethod isEqual:@"POST"]);
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:connectionRequest.HTTPBody options:0 error:nil];
    CHECK([body[@"model"] isEqual:@"offline-model"] && [body[@"messages"] count] == 2);
    CHECK([body[@"messages"][0][@"content"] isEqual:SGLyricsTranslationInstruction()]);
    CHECK([body[@"messages"][1][@"content"] isEqual:SGLyricsTranslationPrompt(@[@"The sky is blue."], @"ko")]);
    NSMutableDictionary *errors = [NSMutableDictionary dictionary];
    for (NSNumber *status in @[@401, @403, @400, @404, @429, @500, @503, @599])
        errors[status] = connectionResult(connectionData(@"connection-fixture-key http://100.97.8.81 secret upstream detail"), status.integerValue, nil, NO);
    CHECK([errors[@401] isEqual:errors[@403]] && [errors[@400] isEqual:errors[@404]]);
    CHECK([errors[@429] isEqual:errors[@500]] && [errors[@503] isEqual:errors[@599]]);
    CHECK(![errors[@401] isEqual:errors[@400]] && ![errors[@400] isEqual:errors[@429]]);
    connectionResult(nil, 0, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost userInfo:@{NSLocalizedDescriptionKey:@"connection-fixture-key"}], NO);
    for (NSData *data in @[[NSData data], [@"invalid JSON" dataUsingEncoding:NSUTF8StringEncoding], connectionData(@""), connectionData(@" \n "), connectionData(@"connection-fixture-key"), connectionData([@"x" stringByPaddingToLength:513 withString:@"x" startingAtIndex:0]), [NSMutableData dataWithLength:512 * 1024 + 1]]) connectionResult(data, 200, nil, NO);
    connectionResult(connectionData([@"x" stringByPaddingToLength:512 withString:@"x" startingAtIndex:0]), 200, nil, YES);
    // Explicit cancel, each changed setting with/without notification, and unchanged generic redraw.
    for (NSNumber *notify in @[@0, @1, @2]) for (NSString *change in @[@"cancel", @"base", @"model", @"key", @"target", @"redraw"]) {
        connectionConfigure(); calls = 0;
        test = SGTestOpenAITranslation(^(NSString *answer, NSString *error) { CHECK(NSThread.isMainThread && answer && !error); calls++; });
        if ([change isEqual:@"cancel"]) [test cancel];
        else if ([change isEqual:@"base"]) [NSUserDefaults.standardUserDefaults setObject:@"http://100.97.8.81:10101/v2" forKey:SGKeyLyricsOpenAIBaseURL];
        else if ([change isEqual:@"model"]) [NSUserDefaults.standardUserDefaults setObject:@"different-model" forKey:SGKeyLyricsOpenAIModel];
        else if ([change isEqual:@"key"]) openAIKeys[@"100.97.8.81"] = [@"replacement-fixture-key" dataUsingEncoding:NSUTF8StringEncoding];
        else if ([change isEqual:@"target"]) testLanguage = @"ja";
        if (notify.boolValue || [change isEqual:@"redraw"]) {
            NSNotificationName name = notify.integerValue == 1 ? SGLyricsTranslationServiceSettingsDidChangeNotification : SGLyricsTranslationsDidChangeNotification;
            [NSNotificationCenter.defaultCenter postNotificationName:name object:nil];
        }
        BOOL redraw = [change isEqual:@"redraw"];
        if (notify.boolValue && !redraw) CHECK(connectionTask.cancelled);
        connectionReply(connectionData(@"하늘은 파랗다."), 200, nil);
        connectionDrain(); CHECK(calls == (redraw ? 1 : 0));
        if (!redraw) CHECK(connectionTask.cancelled);
        connectionReply = nil;
    }
    for (NSString *key in settings) { if (saved[key] == NSNull.null) [NSUserDefaults.standardUserDefaults removeObjectForKey:key]; else [NSUserDefaults.standardUserDefaults setObject:saved[key] forKey:key]; }
    testKeys = savedKeys; openAIKeys = savedOpenAIKeys; testLanguage = savedLanguage;
    puts("Connection fixtures: no key/no send, exact host/model/auth/fixed prompt, safe errors, single completion, cancellation and stale configuration passed");
    checkConnectionTransport();
}
