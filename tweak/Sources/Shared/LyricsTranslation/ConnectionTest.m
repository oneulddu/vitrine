#import "Core/SGCore.h"
#import "AIServicesInternal.h"
#import "ConnectionTest.h"

@interface SGTranslationConnectionTest ()
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic, copy) NSURLRequest *request;
@property (nonatomic, copy) NSArray *observers;
@property (nonatomic, copy) void (^done)(NSString *, NSString *);
@property (nonatomic) BOOL cancelled;
@end
static NSURLRequest *testRequest(NSString **problem) {
    NSString *prompt = SGLyricsTranslationPrompt(@[@"The sky is blue."], SGLyricsGeminiLanguage());
    if (!prompt) { *problem = SGL(@"settings.translation.openai.error.settings", @"Check the translation service's base URL and model on the Lyrics page."); return nil; }
    return SGOpenAIRequest(SGLyricsTranslationInstruction(), prompt, problem);
}
@implementation SGTranslationConnectionTest
- (void)removeObservers {
    for (id observer in self.observers) [NSNotificationCenter.defaultCenter removeObserver:observer];
    self.observers = nil;
}
- (void)dealloc { for (id observer in _observers) [NSNotificationCenter.defaultCenter removeObserver:observer]; }
- (void)cancel {
    self.cancelled = YES;
    [self.task cancel]; self.task = nil; self.request = nil; self.done = nil;
    [self removeObservers];
}
- (BOOL)matchesConfiguration {
    NSString *problem = nil;
    NSURLRequest *now = testRequest(&problem);
    return now && [now.URL isEqual:self.request.URL] && [now.HTTPBody isEqual:self.request.HTTPBody] &&
        [[now valueForHTTPHeaderField:@"Authorization"] isEqual:[self.request valueForHTTPHeaderField:@"Authorization"]];
}
- (void)complete:(NSString *)translation problem:(NSString *)problem {
    if (self.cancelled || !self.done) return;
    void (^done)(NSString *, NSString *) = self.done;
    self.done = nil; self.task = nil; self.request = nil;
    [self removeObservers];
    done(translation, problem);
}
- (void)start {
    NSString *problem = nil;
    self.request = testRequest(&problem);
    if (!self.request) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self complete:nil problem:problem]; });
        return;
    }
    __weak SGTranslationConnectionTest *weakSelf = self;
    NSMutableArray *observers = [NSMutableArray array];
    for (NSNotificationName name in @[SGLyricsTranslationServiceSettingsDidChangeNotification, SGLyricsTranslationsDidChangeNotification]) {
        [observers addObject:[NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            void (^check)(void) = ^{ SGTranslationConnectionTest *test = weakSelf; if (test && ![test matchesConfiguration]) [test cancel]; };
            if (NSThread.isMainThread) check(); else dispatch_async(dispatch_get_main_queue(), check);
        }]];
    }
    self.observers = observers;
    self.task = SGLyricsTranslationSendOnce(self.request, ^(NSData *data, NSInteger status, NSError *error) {
        if (self.cancelled || !self.done) return;
        if (![self matchesConfiguration]) { [self cancel]; return; }
        NSString *failure = nil, *translation = nil;
        if (error) failure = SGL(@"settings.translation.openai.error.unreachable", @"The translation service could not be reached.");
        else if (status == 401 || status == 403) failure = SGL(@"settings.translation.openai.error.keyinvalid", @"The translation service turned the key down. Check it on the Lyrics page.");
        else if (status == 400 || status == 404) failure = SGL(@"settings.translation.openai.error.settings", @"Check the translation service's base URL and model on the Lyrics page.");
        else if (status == 429 || (status >= 500 && status <= 599)) failure = SGL(@"settings.translation.openai.error.busy", @"The translation service is busy right now. Try again in a minute.");
        else if (status == 200 && data.length <= 512 * 1024) {
            id root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSArray *answer = SGOpenAITranslationsIn(root, 1);
            NSString *text = answer.firstObject;
            NSString *auth = [self.request valueForHTTPHeaderField:@"Authorization"];
            NSString *key = [auth hasPrefix:@"Bearer "] ? [auth substringFromIndex:7] : nil;
            if (text.length <= 512 && [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length &&
                (!key.length || [text rangeOfString:key].location == NSNotFound)) translation = text;
        }
        if (!translation && !failure) failure = SGL(@"settings.translation.openai.error.unreadable", @"The translation service's answer could not be read. Try again.");
        [self complete:translation problem:failure];
    });
}
@end
SGTranslationConnectionTest *SGTestOpenAITranslation(void (^done)(NSString *, NSString *)) {
    SGTranslationConnectionTest *test = [SGTranslationConnectionTest new];
    test.done = done;
    [test start];
    return test;
}
