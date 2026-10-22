// The OpenAI-compatible service's two explicit checks on the Lyrics page (ConnectionTest.h). Check connection is a
// model-list request only: it tells reachability and a readable model list apart from a failed one, and sends no
// translation request. Test translation is the one request that may be charged, only from its own tap, with the cost
// in its subtitle. A model list does not verify the key on a public endpoint, so its pass says only that.
// Saved is not the same as working, so each row reads which it is: not tested, testing, works or failed. A tap while
// a row tests cancels it without sending anything else. Any change to the services or the target language drops the
// results, and a missing key stays visible as an actionable failure instead of hiding the rows.
#import "Core/SGCore.h"
#import "Core/SGGlass.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "LyricsTranslation.h"
#import "ConnectionTest.h"

typedef NS_ENUM(NSInteger, SGConnectionTestState) {
    SGConnectionTestUntested, SGConnectionTestRunning, SGConnectionTestPassed, SGConnectionTestFailed
};

@interface SGConnectionRow : NSObject
@property (nonatomic) SGConnectionTestKind kind;
@property (nonatomic) SGConnectionTestState state;
@property (nonatomic, strong) SGTranslationConnectionTest *test;
@property (nonatomic, copy) NSString *problem;      // the safe problem text of a failed check; nil when it passed
@property (nonatomic, copy) NSString *diagnostic;   // safe, copyable details
@property (nonatomic, copy) NSString *language;     // the target language the test or its result belongs to
@property (nonatomic) NSUInteger generation;
@end
@implementation SGConnectionRow
@end

static SGConnectionRow *sg_modelsCheck, *sg_translationCheck;
static void startTest(SGConnectionRow *check, UIViewController *over);

static SGConnectionRow *checkFor(SGConnectionTestKind kind) {
    if (kind == SGConnectionTestModels) {
        if (!sg_modelsCheck) { sg_modelsCheck = [SGConnectionRow new]; sg_modelsCheck.kind = kind; }
        return sg_modelsCheck;
    }
    if (!sg_translationCheck) { sg_translationCheck = [SGConnectionRow new]; sg_translationCheck.kind = kind; }
    return sg_translationCheck;
}

static void forgetResult(SGConnectionRow *check) {
    [check.test cancel];
    check.test = nil;
    check.problem = nil;
    check.diagnostic = nil;
    check.language = nil;
    check.state = SGConnectionTestUntested;
    check.generation++;
}

// Installed once, on the first row. Both notifications are posted on main; another thread is moved there.
static void watchSettings(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void (^onMain)(dispatch_block_t) = ^(dispatch_block_t work) {
            if (NSThread.isMainThread) work(); else dispatch_async(dispatch_get_main_queue(), work);
        };
        [NSNotificationCenter.defaultCenter addObserverForName:SGLyricsTranslationServiceSettingsDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) { onMain(^{
            forgetResult(checkFor(SGConnectionTestModels));
            forgetResult(checkFor(SGConnectionTestTranslation));
        }); }];
        // Posted for saved translations and display switches too: only a new target language matters here.
        [NSNotificationCenter.defaultCenter addObserverForName:SGLyricsTranslationsDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            onMain(^{
                NSString *language = SGLyricsGeminiLanguage();
                for (NSNumber *kind in @[@(SGConnectionTestModels), @(SGConnectionTestTranslation)]) {
                    SGConnectionRow *check = checkFor(kind.integerValue);
                    if (check.state == SGConnectionTestUntested) continue;
                    if (!(language == check.language || [language isEqualToString:check.language])) forgetResult(check);
                }
            });
        }];
    });
}

static void showResult(SGConnectionRow *check, UIViewController *over) {
    BOOL models = check.kind == SGConnectionTestModels;
    if (check.state != SGConnectionTestPassed && check.state != SGConnectionTestFailed) return;
    BOOL passed = check.state == SGConnectionTestPassed;
    NSString *title = passed
        ? (models ? SGL(@"settings.translation.openai.diagnose.models.passed.title", @"Connection and model list work")
                  : SGL(@"settings.translation.openai.test.passed.title", @"Translation works"))
        : (models ? SGL(@"settings.translation.openai.diagnose.models.failed.title", @"Connection check failed")
                  : SGL(@"settings.translation.openai.test.failed.title", @"Test failed"));
    NSString *message = passed
        ? (models ? SGL(@"settings.translation.openai.diagnose.models.passed.message", @"The service returned a readable model list. This does not verify the key or prove every model can translate.")
                  : SGL(@"settings.translation.openai.test.passed.message", @"The service returned a correctly formatted response to the test translation request."))
        : check.problem ?: SGL(@"settings.translation.openai.test.failed.message", @"The service did not translate the test sentence.");
    if (check.diagnostic.length) message = [message stringByAppendingFormat:@"\n\n%@", check.diagnostic];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    NSString *details = check.diagnostic;
    if (details.length) [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.translation.openai.diagnose.copy", @"Copy details") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        // Only the safe diagnostic line: no key, header, URL, query or body.
        UIPasteboard.generalPasteboard.string = details;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.translation.openai.test.again", @"Test Again") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        startTest(check, over);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.ok", @"OK") style:UIAlertActionStyleCancel handler:nil]];
    SGPresentDark(alert);
    [over presentViewController:alert animated:YES completion:nil];
}

// One test at a time per row. The result shows over the page it was asked from, only while that page is still on top;
// otherwise the row keeps it for the next look.
static void startTest(SGConnectionRow *check, UIViewController *over) {
    if (check.state == SGConnectionTestRunning) return;
    forgetResult(check);
    NSUInteger generation = check.generation;
    check.language = SGLyricsGeminiLanguage();
    check.state = SGConnectionTestRunning;
    __weak UIViewController *weakOver = over;
    SGTranslationConnectionTest *test = SGTestOpenAIConnection(check.kind, ^(SGTranslationConnectionReport *report) {
        if (generation != check.generation) return;   // settings changed or a new test began meanwhile
        check.test = nil;
        // Success needs its own evidenced fact, never merely the absence of a problem: a readable model list for the
        // model check, a parsed sample answer for the translation check. Returned sample text is not kept or shown.
        BOOL checked = check.kind == SGConnectionTestModels ? report.models == SGConnectionFactYes
                                                           : report.translated == SGConnectionFactYes;
        BOOL passed = report && checked && !report.problem.length;
        check.state = passed ? SGConnectionTestPassed : SGConnectionTestFailed;
        check.problem = passed ? nil : (report.problem.length ? report.problem
                                                             : SGL(@"settings.translation.openai.test.failed.message", @"The service did not translate the test sentence."));
        check.diagnostic = report.diagnostic;
        UIViewController *page = weakOver;
        if (page && page.viewIfLoaded.window && !page.presentedViewController && SGTopController() == page) showResult(check, page);
    });
    if (check.state != SGConnectionTestRunning) return;   // answered before the handle was kept
    check.test = test;
    if (!test) {
        // Refused before sending (nothing to test yet): the next tap may ask again.
        check.state = SGConnectionTestUntested;
        check.language = nil;
    }
}

// Both rows stay visible without a key: a tap then explains it. Facts stay separate: the model row's failure never
// claims the translation would fail, and vice versa.
static SGModRow *checkRow(SGConnectionTestKind kind) {
    watchSettings();
    SGConnectionRow *check = checkFor(kind);
    BOOL models = kind == SGConnectionTestModels;
    SGModRow *row = SGStatActionRow(models ? SGL(@"settings.translation.openai.diagnose.models.title", @"Check connection")
                                           : SGL(@"settings.translation.openai.test.title", @"Test translation"),
        models ? SGL(@"settings.translation.openai.diagnose.models.subtitle", @"Checks the address and model list without sending a translation request.")
               : SGL(@"settings.translation.openai.test.subtitle", @"Sends one short sentence with the saved service, model and key. The service may charge for it"),
        ^NSString *{
            switch (check.state) {
                case SGConnectionTestRunning: return SGL(@"settings.translation.openai.test.running", @"Testing… · Cancel");
                case SGConnectionTestPassed: return SGL(@"settings.translation.openai.test.passed", @"✓ Works");
                case SGConnectionTestFailed: return SGL(@"settings.translation.openai.test.failed", @"✕ Failed");
                default: return SGOpenAIKeySet() ? SGL(@"settings.translation.openai.test.untested", @"Not tested")
                                                : SGL(@"settings.translation.openai.test.nokey", @"API key required");
            }
        }, ^{
            UIViewController *page = SGTopController();
            if (check.state == SGConnectionTestRunning) forgetResult(check);   // cancels; sends nothing new
            else if (check.state == SGConnectionTestPassed || check.state == SGConnectionTestFailed) showResult(check, page);
            else startTest(check, page);
        });
    return row;
}

SGModRow *SGOpenAIConnectionTestRow(void) {
    return checkRow(SGConnectionTestModels);
}

SGModRow *SGOpenAITranslationTestRow(void) {
    return checkRow(SGConnectionTestTranslation);
}
