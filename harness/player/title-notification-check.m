// Exercise production viewDidLoad and NSNotificationCenter delivery, never call the title handlers directly.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "title-notification-stubs.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Lyrics/SGRKaraokeView.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"

// Interface only: implementation is the complete Logos-processed production PlayerLandscape.x.
@interface SGRLandscapeLyricsController : UIViewController
- (void)setControlsShown:(BOOL)shown;
- (void)restartRest;
@end

static int failed, checked;
static NSUInteger restCalls, controlsCalls, idleWrites;
static void (*originalRest)(id, SEL);
static void (*originalControls)(id, SEL, BOOL);
static void (*originalIdle)(id, SEL, BOOL);
static SGRLandscapeLyricsController *screen;
static NSDictionary *before;
static NSUInteger previousReads;

static void check(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what.UTF8String);
    fflush(stdout);
    checked++;
    if (!ok) failed++;
}
static void countedRest(id self, SEL cmd) {
    restCalls++;
    originalRest(self, cmd);
}
static void countedControls(id self, SEL cmd, BOOL shown) {
    controlsCalls++;
    originalControls(self, cmd, shown);
}
static void countedIdle(id self, SEL cmd, BOOL disabled) {
    idleWrites++;
    originalIdle(self, cmd, disabled);
}
static void installCounters(void) {
    Method method = class_getInstanceMethod(SGRLandscapeLyricsController.class, @selector(restartRest));
    originalRest = (void *)method_setImplementation(method, (IMP)countedRest);
    method = class_getInstanceMethod(SGRLandscapeLyricsController.class, @selector(setControlsShown:));
    originalControls = (void *)method_setImplementation(method, (IMP)countedControls);
    method = class_getInstanceMethod(UIApplication.class, @selector(setIdleTimerDisabled:));
    originalIdle = (void *)method_setImplementation(method, (IMP)countedIdle);
}
static id orNull(id value) { return value ?: NSNull.null; }
// KVC is unsafe here: "rest" invokes -rest and "title" resolves UIViewController.title.
// Read object ivars directly so the assertions themselves cannot wake/hide the controls.
static id field(id controller, NSString *name) {
    Ivar ivar = class_getInstanceVariable(SGRLandscapeLyricsController.class,
                                        [@"_" stringByAppendingString:name].UTF8String);
    NSCAssert(ivar != NULL, @"Missing production ivar %@", name);
    return object_getIvar(controller, ivar);
}
static NSDictionary *snapshot(SGRLandscapeLyricsController *controller) {
    NSTimer *timer = field(controller, @"rest");
    UIView *shield = field(controller, @"shield");
    UIButton *play = field(controller, @"play");
    NSMutableArray *alphas = [NSMutableArray array];
    for (NSString *key in @[@"controls", @"close", @"title", @"artist", @"stage"]) {
        UIView *view = field(controller, key);
        [alphas addObject:@(view.alpha)];
    }
    return @{
        @"rest": orNull(timer), @"fireDate": orNull([timer.fireDate copy]), @"valid": @(timer.valid),
        @"shield": orNull(shield.superview), @"alphas": alphas,
        @"hideEnabled": @(((UIGestureRecognizer *)field(controller, @"hide")).enabled),
        @"extrasHidden": @(((SGRKaraokeView *)field(controller, @"lyrics")).extrasHidden),
        @"bare": [controller valueForKey:@"bare"],
        @"motionHeld": @(((SGRArtworkField *)field(controller, @"field")).motionHeld),
        @"playLabel": orNull(play.accessibilityLabel), @"playImage": orNull([play imageForState:UIControlStateNormal]),
        @"state": orNull(SGPlayerState()),
        @"idleDisabled": @(UIApplication.sharedApplication.idleTimerDisabled),
        @"idleWrites": @(idleWrites), @"restCalls": @(restCalls), @"controlsCalls": @(controlsCalls)
    };
}
static void unchanged(NSString *context) {
    NSDictionary *after = snapshot(screen);
    NSMutableArray *changed = [NSMutableArray array];
    for (NSString *key in before) if (![before[key] isEqual:after[key]]) [changed addObject:key];
    check(changed.count == 0, [NSString stringWithFormat:@"%@: no timer, shield, alpha, playback or idle side effects%@",
        context, changed.count ? [@"; changed: " stringByAppendingString:[changed componentsJoinedByString:@", "]] : @""]);
}
static void textIs(NSString *title, NSString *artist, NSString *context) {
    SGMarqueeLabel *titleLabel = field(screen, @"title");
    SGMarqueeLabel *artistLabel = field(screen, @"artist");
    check([titleLabel.text isEqual:title] && [artistLabel.text isEqual:artist], context);
    check([titleLabel.accessibilityLabel isEqual:title] && [artistLabel.accessibilityLabel isEqual:artist],
          [context stringByAppendingString:@" (accessibility labels)"]);
}
static void post(NSNotificationName name, id object) {
    [NSNotificationCenter.defaultCenter postNotificationName:name object:object];
}
// Model an asynchronous provider completion that publishes on main, as TranslatedTitles.m does.
static void asyncTitle(NSString *track, dispatch_block_t continuation) {
    dispatch_async(dispatch_get_main_queue(), ^{
        check(NSThread.isMainThread, @"asynchronous title event delivered on main");
        post(SGTranslatedTitleDidChangeNotification, track);
        continuation();
    });
}
static void finish(void) {
    // Drop the last controller while its production weak-target timer is still scheduled.
    [screen setControlsShown:YES];
    __weak id weakScreen = screen;
    __weak id weakTitle = field(screen, @"title");
    NSTimer *timer = field(screen, @"rest");
    check(timer.valid, @"deallocation fixture has an active rest timer");
    before = nil;
    screen = nil;
    // UIKit's loadView autoreleases may live until this event's pool drains.
    dispatch_async(dispatch_get_main_queue(), ^{
        check(weakScreen == nil && weakTitle == nil, @"notification observers do not retain controller or title label");
        check(!timer.valid, @"controller dealloc invalidates the active rest timer");
        check(SGTitleHarnessObserverCount() == 0, @"player-state weak observer released");
        NSUInteger count = SGTitleHarnessReads();
        post(SGTranslatedTitleDidChangeNotification, @"B");
        post(SGTitleTranslationSettingsDidChangeNotification, nil);
        check(SGTitleHarnessReads() == count, @"both notifications after deallocation are safe and do not refresh title");
        printf("landscape title notifications: %d/%d passed\n", checked - failed, checked);
        fflush(stdout);
        exit(failed ? 1 : 0);
    });
}
static void edgeCases(void) {
    // Non-track and malformed URIs cannot match a translated track event.
    for (id uri in @[@"spotify:local:artist:album:song:123", @"spotify:episode:E", @42, NSNull.null]) {
        SGTitleHarnessState(uri == NSNull.null ? nil : uri, @"Local title", @"Local artist", NO);
        before = snapshot(screen);
        previousReads = SGTitleHarnessReads();
        post(SGTranslatedTitleDidChangeNotification, @"B");
        post(SGTranslatedTitleDidChangeNotification, nil);
        check(SGTitleHarnessReads() == previousReads, [NSString stringWithFormat:@"non-track URI %@ ignores title completion", uri]);
        textIs(@"Local title", @"Local artist", @"non-track metadata preserved");
        unchanged(@"non-track event");
        post(SGTitleTranslationSettingsDidChangeNotification, nil);
        check(SGTitleHarnessReads() == previousReads + 1, @"settings refresh also accepts non-track metadata");
        unchanged(@"non-track settings");
    }
    SGTitleHarnessClearState();
    before = snapshot(screen);
    previousReads = SGTitleHarnessReads();
    post(SGTranslatedTitleDidChangeNotification, @"B");
    post(SGTitleTranslationSettingsDidChangeNotification, nil);
    check(SGTitleHarnessReads() == previousReads, @"no player state: both events are harmless");
    unchanged(@"no player state");
    SGTitleHarnessState(@"spotify:track:B", @"Song B", @"Artist B", NO);
    finish();
}
static void settingsAndPause(void) {
    SGTitleHarnessUseTranslations(NO);
    before = snapshot(screen);
    previousReads = SGTitleHarnessReads();
    post(SGTitleTranslationSettingsDidChangeNotification, nil);
    textIs(@"Song B", @"Artist B", @"settings disable refreshes both labels without player-state event");
    check(SGTitleHarnessReads() == previousReads + 1, @"one settings event performs exactly one title read");
    unchanged(@"settings while hidden");
    SGTitleHarnessUseTranslations(YES);
    post(SGTitleTranslationSettingsDidChangeNotification, nil);
    textIs(@"번역 B", @"가수 B", @"settings re-enable restores cached title and artist");
    unchanged(@"settings re-enable while hidden");

    SGTitleHarnessState(@"spotify:track:B", @"Song B", @"Artist B", YES);
    check(field(screen, @"rest") == nil, @"paused fixture has no rest timer");
    SGTitleHarnessAnswer(@"B", @"Paused translation", @"Paused artist");
    before = snapshot(screen);
    post(SGTranslatedTitleDidChangeNotification, @"B");
    textIs(@"Paused translation", @"Paused artist", @"title event refreshes paused track");
    unchanged(@"paused title event");
    post(SGTitleTranslationSettingsDidChangeNotification, nil);
    unchanged(@"paused settings event");
    edgeCases();
}
static void afterTrackChange(void) {
    textIs(@"Song B", @"Artist B", @"late completion for previous track does not replace current track");
    check(SGTitleHarnessReads() == previousReads, @"previous-track event never queries title provider");
    unchanged(@"previous-track completion");
    SGTitleHarnessAnswer(@"B", @"번역 B", @"가수 B");
    previousReads = SGTitleHarnessReads();
    asyncTitle(@"B", ^{
        textIs(@"번역 B", @"가수 B", @"current NSURL track gets async title and artist");
        check(SGTitleHarnessReads() == previousReads + 1, @"current-track event reads provider exactly once");
        unchanged(@"current-track completion while hidden");
        settingsAndPause();
    });
}
static void afterVisibleCompletion(void) {
    textIs(@"번역 A", @"가수 A", @"async translation updates actual title and artist labels");
    check(SGTitleHarnessReads() == previousReads + 1, @"subscription delivers exactly one title refresh");
    unchanged(@"title completion with visible controls");
    previousReads = SGTitleHarnessReads();
    post(SGTranslatedTitleDidChangeNotification, @"unrelated");
    post(SGTranslatedTitleDidChangeNotification, nil);
    post(SGTranslatedTitleDidChangeNotification, @17);
    check(SGTitleHarnessReads() == previousReads, @"unrelated, nil and malformed event objects ignored");
    unchanged(@"irrelevant events");

    [screen setControlsShown:NO];
    check(field(screen, @"rest") == nil && ((UIView *)field(screen, @"shield")).superview == screen.view &&
          ((UIView *)field(screen, @"controls")).alpha == 0, @"hidden fixture has shield, zero controls alpha and no timer");
    SGTitleHarnessState([NSURL URLWithString:@"spotify:track:B"], @"Song B", @"Artist B", NO);
    textIs(@"Song B", @"Artist B", @"player-state observer changes to track B");
    before = snapshot(screen);
    previousReads = SGTitleHarnessReads();
    SGTitleHarnessAnswer(@"A", @"Stale A", @"Stale artist A");
    asyncTitle(@"A", ^{ afterTrackChange(); });
}
static void runChecks(void) {
    installCounters();
    SGTitleHarnessState(@"spotify:track:A", @"Song A", @"Artist A", NO);
    screen = [SGRLandscapeLyricsController new];
    [screen loadViewIfNeeded];
    screen.view.frame = CGRectMake(0, 0, 844, 390);
    [screen.view layoutIfNeeded];
    textIs(@"Song A", @"Artist A", @"real controller viewDidLoad reads original title and artist");
    check(SGTitleHarnessObserverCount() == 1, @"real controller registers its player-state observer");
    NSTimer *timer = field(screen, @"rest");
    check(timer.valid && ((UIView *)field(screen, @"shield")).superview == nil &&
          ((UIView *)field(screen, @"controls")).alpha == 1, @"visible fixture has active timer and no shield");
    before = snapshot(screen);
    previousReads = SGTitleHarnessReads();
    SGTitleHarnessAnswer(@"A", @"번역 A", @"가수 A");
    textIs(@"Song A", @"Artist A", @"provider completion alone does not change labels before notification");
    asyncTitle(@"A", ^{ afterVisibleCompletion(); });
}

@interface SGTitleCheckApp : UIResponder <UIApplicationDelegate>
@end
@implementation SGTitleCheckApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    // A failed launch/continuation is a bounded failure, not a hanging green test.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        fputs("FAIL landscape title checks timed out\n", stderr);
        exit(1);
    });
    dispatch_async(dispatch_get_main_queue(), ^{ runChecks(); });
    return YES;
}
@end
@interface SGTitleCheckScene : UIResponder <UIWindowSceneDelegate>
@end
@implementation SGTitleCheckScene
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGTitleCheckApp.class)); }
}
