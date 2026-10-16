// Explicit short-sentence test of the saved OpenAI-compatible configuration, not a lyric request.
#import <Foundation/Foundation.h>
@class SGModRow;
@interface SGTranslationConnectionTest : NSObject
// Cancels transport and makes a later completion silent. Main thread.
- (void)cancel;
@end
// Exactly one bounded request, no retries/redirects; no key, URL or upstream error body in the message.
// Main-thread completion. Settings/target changes cancel the test and its old result.
SGTranslationConnectionTest *SGTestOpenAITranslation(void (^done)(NSString *translation, NSString *problem));
SGModRow *SGOpenAIConnectionTestRow(void);
