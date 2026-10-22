// The saved OpenAI-compatible configuration checked in two separate steps: a model-list request that
// checks reachability (not key validity on a public endpoint), and an explicit sample translation that may be charged.
// Neither is sent on render; each runs only from its row's tap.
#import <Foundation/Foundation.h>
@class SGModRow;

// Which part of the configuration an outcome belongs to.
typedef NS_ENUM(NSInteger, SGConnectionCheck) {
    SGConnectionCheckConfiguration,   // nothing saved, or an address/model that cannot form a request
    SGConnectionCheckConnection,      // transport: ATS, DNS, refused, timeout, offline
    SGConnectionCheckAuthentication,  // an HTTP reply rejected the key
    SGConnectionCheckModels,          // the model list: usable, missing, or the translation request refused
    SGConnectionCheckTranslation,     // the sample reply: read, or not
};
// Separate facts, never one guess: a 401 proves transport works but authentication failed; a 404 model list is
// not proof that chat fails, so the translation row can still be tried on its own.
typedef NS_ENUM(NSInteger, SGConnectionFact) { SGConnectionFactUnknown, SGConnectionFactYes, SGConnectionFactNo };
typedef NS_ENUM(NSInteger, SGConnectionTestKind) { SGConnectionTestModels, SGConnectionTestTranslation };

@interface SGTranslationConnectionReport : NSObject
@property (nonatomic) SGConnectionCheck stage;
@property (nonatomic) SGConnectionFact reachable, authenticated, models, translated;
@property (nonatomic, copy) NSString *problem;      // a safe sentence for the user; nil when this check passed
// The sample is validated but never retained or exposed: even a well-shaped answer can echo secrets.
// Copyable details contain only bounded diagnostic facts. Never the key, Authorization, model name,
// the URL or query, arbitrary error text, a request or response body, or lyrics.
@property (nonatomic, copy) NSString *diagnostic;
@end

@interface SGTranslationConnectionTest : NSObject
// Cancels transport and makes a later completion silent. Main thread.
- (void)cancel;
@end

// Exactly one bounded request of `kind`, no retries/redirects. The model check is a GET /models and sends no
// lyrics or generation. Main-thread completion. Settings/target changes cancel the test and its old result.
SGTranslationConnectionTest *SGTestOpenAIConnection(SGConnectionTestKind kind, void (^done)(SGTranslationConnectionReport *report));
// Both rows stay visible without a key, where they say what to do instead of disappearing.
SGModRow *SGOpenAIConnectionTestRow(void);
SGModRow *SGOpenAITranslationTestRow(void);
