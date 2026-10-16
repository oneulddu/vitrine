// The Lyrics page's Test connection row for the OpenAI-compatible service: one short sentence, sent only when tapped,
// with the saved address, model and key (ConnectionTest.h). Saved is not the same as working, so the row reads which
// it is: not tested, testing, works or failed. A tap while it tests cancels it without sending anything else. Any
// change to the services or the target language drops the result.
#import "Core/SGCore.h"
#import "Core/SGGlass.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "LyricsTranslation.h"
#import "ConnectionTest.h"

typedef NS_ENUM(NSInteger, SGConnectionTestState) {
    SGConnectionTestUntested, SGConnectionTestRunning, SGConnectionTestPassed, SGConnectionTestFailed
};

static SGConnectionTestState sg_state;
static SGTranslationConnectionTest *sg_test;
static NSString *sg_answer;     // the translation, or the safe problem text
static NSString *sg_language;   // the target language the test or its result belongs to
static NSUInteger sg_generation;
static void startTest(UIViewController *over);

static void forgetResult(void) {
    [sg_test cancel];
    sg_test = nil;
    sg_answer = nil;
    sg_language = nil;
    sg_state = SGConnectionTestUntested;
    sg_generation++;
}

// Installed once, on the first row. Both notifications are posted on main; another thread is moved there.
static void watchSettings(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void (^onMain)(dispatch_block_t) = ^(dispatch_block_t work) {
            if (NSThread.isMainThread) work(); else dispatch_async(dispatch_get_main_queue(), work);
        };
        [NSNotificationCenter.defaultCenter addObserverForName:SGLyricsTranslationServiceSettingsDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) { onMain(^{ forgetResult(); }); }];
        // Posted for saved translations and display switches too: only a new target language matters here.
        [NSNotificationCenter.defaultCenter addObserverForName:SGLyricsTranslationsDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            onMain(^{
                if (sg_state == SGConnectionTestUntested) return;
                NSString *language = SGLyricsGeminiLanguage();
                if (!(language == sg_language || [language isEqualToString:sg_language])) forgetResult();
            });
        }];
    });
}

static void showResult(UIViewController *over) {
    if (sg_state != SGConnectionTestPassed && sg_state != SGConnectionTestFailed) return;
    BOOL passed = sg_state == SGConnectionTestPassed;
    NSString *message = passed
        ? [NSString stringWithFormat:SGL(@"settings.translation.openai.test.passed.message", @"Test translation: %@"), sg_answer ?: @""]
        : sg_answer ?: SGL(@"settings.translation.openai.test.failed.message", @"The service did not translate the test sentence.");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:passed ? SGL(@"settings.translation.openai.test.passed.title", @"Connection works")
                                                                                   : SGL(@"settings.translation.openai.test.failed.title", @"Test failed")
                                                                   message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.translation.openai.test.again", @"Test Again") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        startTest(over);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.ok", @"OK") style:UIAlertActionStyleCancel handler:nil]];
    SGPresentDark(alert);
    [over presentViewController:alert animated:YES completion:nil];
}

// One test at a time. The result shows over the page it was asked from, only while that page is still on top;
// otherwise the row keeps it for the next look.
static void startTest(UIViewController *over) {
    if (sg_state == SGConnectionTestRunning || !SGOpenAIKeySet()) return;
    forgetResult();
    NSUInteger generation = sg_generation;
    sg_language = SGLyricsGeminiLanguage();
    sg_state = SGConnectionTestRunning;
    __weak UIViewController *weakOver = over;
    SGTranslationConnectionTest *test = SGTestOpenAITranslation(^(NSString *translation, NSString *problem) {
        if (generation != sg_generation) return;   // settings changed or a new test began meanwhile
        sg_test = nil;
        BOOL passed = translation.length && !problem.length;
        sg_state = passed ? SGConnectionTestPassed : SGConnectionTestFailed;
        sg_answer = passed ? translation : problem;
        UIViewController *page = weakOver;
        if (page && page.viewIfLoaded.window && !page.presentedViewController && SGTopController() == page) showResult(page);
    });
    if (sg_state != SGConnectionTestRunning) return;   // answered at once
    sg_test = test;
    if (!test) {
        // Refused before sending (nothing saved to test): the next tap may ask again.
        sg_state = SGConnectionTestUntested;
        sg_language = nil;
    }
}

SGModRow *SGOpenAIConnectionTestRow(void) {
    watchSettings();
    SGModRow *row = SGStatActionRow(SGL(@"settings.translation.openai.test.title", @"Test connection"),
        SGL(@"settings.translation.openai.test.subtitle", @"Sends one short sentence with the saved service, model and key. The service may charge for it"),
        ^NSString *{
            switch (sg_state) {
                case SGConnectionTestRunning: return SGL(@"settings.translation.openai.test.running", @"Testing… · Cancel");
                case SGConnectionTestPassed: return SGL(@"settings.translation.openai.test.passed", @"✓ Works");
                case SGConnectionTestFailed: return SGL(@"settings.translation.openai.test.failed", @"✕ Failed");
                default: return SGL(@"settings.translation.openai.test.untested", @"Not tested");
            }
        }, ^{
            UIViewController *page = SGTopController();
            if (sg_state == SGConnectionTestRunning) forgetResult();   // cancels; sends nothing new
            else if (sg_state == SGConnectionTestPassed || sg_state == SGConnectionTestFailed) showResult(page);
            else startTest(page);
        });
    row.visible = ^BOOL { return SGOpenAIKeySet(); };
    return row;
}
