// Real ConnectionTestSettings.m, SGPage, UIKit and UIAlertController; fake backend/presentation boundary.
#import <UIKit/UIKit.h>
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/LyricsTranslation/ConnectionTest.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"

static int checks, failures;
static NSUInteger starts, cancellations, presentations;
static BOOL hasKey = YES, refuseHandle, synchronousReply;
static NSString *target = @"ko";
static UIViewController *topController;
static UIAlertController *lastAlert;
static UIWindow *window;
static void check(BOOL ok, NSString *label) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", label.UTF8String);
    checks++; if (!ok) failures++;
}
@implementation SGModRow
@end
SGModRow *SGStatActionRow(NSString *title, NSString *subtitle, NSString *(^value)(void), void (^action)(void)) {
    SGModRow *row = [SGModRow new]; row.title = title; row.subtitle = subtitle;
    row.value = value; row.action = action; return row;
}
BOOL SGOpenAIKeySet(void) { return hasKey; }
NSString *SGLyricsGeminiLanguage(void) { return target; }
UIViewController *SGTopController(void) { return topController; }
UIColor *SGPageBackground(void) { return UIColor.blackColor; }
void SGPresentDark(UIViewController *controller) { controller.overrideUserInterfaceStyle = UIUserInterfaceStyleDark; }
NSNotificationName const SGLyricsTranslationsDidChangeNotification = @"FixtureTranslationsChanged";
NSNotificationName const SGLyricsTranslationServiceSettingsDidChangeNotification = @"FixtureServiceSettingsChanged";

@interface SGTranslationConnectionTest ()
@property (nonatomic, copy) void (^reply)(NSString *, NSString *);
@property NSUInteger cancelCalls;
@end
@implementation SGTranslationConnectionTest
- (void)cancel { self.cancelCalls++; cancellations++; }
@end
static SGTranslationConnectionTest *lastTest;
SGTranslationConnectionTest *SGTestOpenAITranslation(void (^done)(NSString *, NSString *)) {
    check(NSThread.isMainThread, @"backend starts on main"); starts++;
    if (refuseHandle) return nil;
    lastTest = [SGTranslationConnectionTest new]; lastTest.reply = done;
    if (synchronousReply) done(@"하늘은 파랗다.", nil);
    return lastTest;
}
// Count actual presentation requests and inspect the real UIAlertController, without animation timing.
@interface CheckPage : SGPage
@property (nonatomic, strong) UIViewController *cover;
@end
@implementation CheckPage
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    check([controller isKindOfClass:UIAlertController.class], @"production presents a real UIAlertController");
    presentations++; lastAlert = (UIAlertController *)controller;
    if (completion) completion();
}
- (UIViewController *)presentedViewController { return self.cover; }
@end
static void post(NSNotificationName name) { [NSNotificationCenter.defaultCenter postNotificationName:name object:nil]; }
static void reset(void) { post(SGLyricsTranslationServiceSettingsDidChangeNotification); lastAlert = nil; }
static CheckPage *visiblePage(void) {
    CheckPage *page = [[CheckPage alloc] initWithStyle:UITableViewStyleInsetGrouped];
    window.rootViewController = page;
    [page loadViewIfNeeded]; [window makeKeyAndVisible];
    [page.view layoutIfNeeded]; topController = page;
    return page;
}
static void runChecks(void) {
    window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 600, 800)];
    CheckPage *page = visiblePage();
    check(NSThread.isMainThread && page.view.window == window && page.overrideUserInterfaceStyle == UIUserInterfaceStyleDark,
          @"real SGPage is attached to a UIKit window with dark appearance");
    SGModRow *row = SGOpenAIConnectionTestRow();
    check(row.action && row.value && row.visible && !row.page, @"production returns an explicit action row");
    check([row.value() isEqual:@"Not tested"] && starts == 0, @"creating/reading row starts no request");
    check([row.subtitle containsString:@"short sentence"] && [row.subtitle containsString:@"charge"], @"row explains test payload and possible charge");
    for (int i = 0; i < 5; i++) { SGModRow *another = SGOpenAIConnectionTestRow(); another.value(); another.visible(); }
    check(starts == 0, @"recreating and redrawing settings never auto-tests");
    hasKey = NO; check(!row.visible(), @"missing key hides test row"); row.action();
    check(starts == 0, @"even direct action cannot start without a key"); hasKey = YES;
    row.action(); SGTranslationConnectionTest *cancelled = lastTest;
    check(starts == 1 && [row.value() isEqual:@"Testing… · Cancel"], @"explicit tap starts once and exposes Cancel");
    row.value(); row.visible(); check(starts == 1, @"running redraw does not start again");
    row.action();
    check(starts == 1 && cancelled.cancelCalls == 1 && [row.value() isEqual:@"Not tested"], @"second tap cancels exactly once without duplicate start");
    NSUInteger shown = presentations;
    cancelled.reply(@"late cancelled result", nil);
    check([row.value() isEqual:@"Not tested"] && presentations == shown, @"cancelled late callback stays silent");

    row.action(); lastTest.reply(@"하늘은 파랗다.", nil);
    check([row.value() isEqual:@"✓ Works"] && presentations == shown + 1, @"visible success shows checkmark and one result alert");
    check([lastAlert.title isEqual:@"Connection works"] && [lastAlert.message containsString:@"하늘은 파랗다."] &&
          ![lastAlert.message containsString:@"Hello"] && ![lastAlert.message containsString:@"Lyrics will"], @"success describes actual test result without promising lyric translation");
    check(lastAlert.overrideUserInterfaceStyle == UIUserInterfaceStyleDark && lastAlert.actions.count == 2 &&
          [lastAlert.actions[0].title isEqual:@"Test Again"] && [lastAlert.actions[1].title isEqual:@"OK"], @"result alert is dark and has Test Again/OK actions");
    NSUInteger before = starts; shown = presentations;
    row.action(); check(starts == before && presentations == shown + 1, @"tapping cached result opens it without a request");
    shown = presentations; post(SGLyricsTranslationsDidChangeNotification);
    check([row.value() isEqual:@"✓ Works"] && presentations == shown && starts == before, @"unrelated redraw preserves completed success silently");
    reset(); row.action(); lastTest.reply(nil, @"The translation service could not be reached.");
    check([row.value() isEqual:@"✕ Failed"] && [lastAlert.title isEqual:@"Test failed"] &&
          [lastAlert.message isEqual:@"The translation service could not be reached."], @"failure uses cross status and safe backend message");
    post(SGLyricsTranslationsDidChangeNotification);
    check([row.value() isEqual:@"✕ Failed"], @"unrelated redraw preserves failure too");
    reset(); row.action(); lastTest.reply(nil, nil);
    check([row.value() isEqual:@"✕ Failed"] && lastAlert.message.length > 0, @"empty backend failure still has explanatory text");

    for (NSNumber *languageChange in @[@NO, @YES]) {
        reset(); row.action(); SGTranslationConnectionTest *old = lastTest;
        if (languageChange.boolValue) target = [target isEqual:@"ko"] ? @"ja" : @"ko";
        post(languageChange.boolValue ? SGLyricsTranslationsDidChangeNotification : SGLyricsTranslationServiceSettingsDidChangeNotification);
        check(old.cancelCalls == 1 && [row.value() isEqual:@"Not tested"], @"service/target change cancels pending request and clears status");
        row.action(); SGTranslationConnectionTest *current = lastTest;
        shown = presentations; old.reply(@"stale settings result", nil);
        check([row.value() isEqual:@"Testing… · Cancel"] && presentations == shown && current.cancelCalls == 0,
              @"old callback cannot overwrite or cancel replacement test");
        post(SGLyricsTranslationsDidChangeNotification);
        check([row.value() isEqual:@"Testing… · Cancel"] && current.cancelCalls == 0, @"unrelated notification leaves pending test alive");
        current.reply(@"current result", nil);
        check([row.value() isEqual:@"✓ Works"] && [lastAlert.message containsString:@"current result"], @"replacement test still completes normally");
        if (languageChange.boolValue) target = [target isEqual:@"ko"] ? @"ja" : @"ko";
        post(languageChange.boolValue ? SGLyricsTranslationsDidChangeNotification : SGLyricsTranslationServiceSettingsDidChangeNotification);
        check([row.value() isEqual:@"Not tested"], @"service/target change also invalidates cached result");
    }
    // Closing a global-state row does not cancel the bounded backend; only popup presentation is suppressed.
    reset(); row.action(); SGTranslationConnectionTest *closed = lastTest; shown = presentations;
    window.rootViewController = [UIViewController new]; topController = window.rootViewController;
    check(page.view.window == nil, @"closed page is genuinely detached from window");
    closed.reply(@"closed-page result", nil);
    check(closed.cancelCalls == 0 && presentations == shown && [row.value() isEqual:@"✓ Works"], @"closed page completes into cache without popping an alert");
    page = visiblePage(); before = starts; row.action();
    check(starts == before && [lastAlert.message containsString:@"closed-page result"], @"returning to settings can inspect cached result without resending");
    reset(); row.action(); shown = presentations; topController = [UIViewController new];
    lastTest.reply(@"not-top result", nil);
    check(presentations == shown && [row.value() isEqual:@"✓ Works"], @"attached page that is not top receives no popup");
    topController = page; reset(); page.cover = [UIViewController new]; row.action(); shown = presentations;
    lastTest.reply(@"covered result", nil);
    check(presentations == shown && [row.value() isEqual:@"✓ Works"], @"existing modal suppresses automatic popup"); page.cover = nil;
    reset(); refuseHandle = YES; row.action(); refuseHandle = NO;
    check([row.value() isEqual:@"Not tested"], @"nil backend handle does not leave UI stuck testing");
    synchronousReply = YES; row.action(); synchronousReply = NO;
    check([row.value() isEqual:@"✓ Works"], @"synchronous backend completion does not leave a running state");
    SGTranslationConnectionTest *finished = lastTest; reset();
    check(finished.cancelCalls == 0, @"synchronous completion does not retain a finished handle for cancellation");
    printf("connection test settings: %d/%d passed; %lu starts, %lu cancels\n", checks - failures, checks,
           (unsigned long)starts, (unsigned long)cancellations); fflush(stdout); exit(failures ? 1 : 0);
}
@interface CheckApp : UIResponder <UIApplicationDelegate>
@end
@implementation CheckApp
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        fputs("FAIL UIKit check timed out\n", stderr); exit(1);
    });
    dispatch_async(dispatch_get_main_queue(), ^{ runChecks(); }); return YES;
}
@end
@interface CheckScene : UIResponder <UIWindowSceneDelegate>
@end
@implementation CheckScene
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(CheckApp.class)); }
}
