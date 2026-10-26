// Mod Settings' main page as App/ModSettings.x builds it, opened the way holding Home opens it
// (SGOpenModSettings), with the real App/Pages.m behind its Redesigned UI switch and the real Settings/
// framework and About page; stubs.m stands in for other pages and actions. The launch line sets the look up and then plays
// actions, one every 0.9 s from 1 s in; screenshot after.
//
//     THEOS=$HOME/theos ./build.sh && xcrun simctl install <udid> build/ModSettingsHarness.app
//     xcrun simctl launch <udid> com.vitrine.modsettingsharness [setup...] [action...]
//
// Setup: redesign (Redesigned UI stored on), warning (a red environment row at the top), keep (the stored
// look stays; otherwise it is cleared first).
// Actions: toggle=<section>.<row> (that row's switch flipped the way a tap does), cancel (the alert that
// switch brings up closed with Later), bottom (scrolled to the end), dump (the rows of each section and
// what each reads beside its chevron, to the log), gated (a page of a switch, ten rows, a headed and noted
// section of twelve rows shown only while the switch is on, and a row that comes by itself), later (that row
// let come; the page's ticker brings it), top (scrolled to the start), layout (the scroll offset, and each
// section's rows and heading and note heights, to the log), needs (the Lock screen artwork section below iOS
// 26), tap=<section>.<row> (that row selected, and the alert it brings up logged), rows (the row the mod adds to
// Spotify's settings list and drawer, after each list is emptied of its subviews, counted to the log).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import <CoreText/SFNTLayoutTypes.h>
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "App/About/About.h"
#import "../harness-fail.h"

// Spotify's page protocol, so SGRegisterPages finds one and the page is pushed as on the phone.
@protocol SPTPageController <NSObject>
@end

// Settings/SGSettingsSearch.m's search rules, tested without a search bar.
NSString *SGSearchInitials(NSString *text);
BOOL SGSearchIsInitialsWord(NSString *word);
BOOL SGSearchWordMatches(NSString *word, NSString *folded, NSString *initials);
BOOL SGSearchStartsTitle(NSString *query, NSString *foldedTitle, NSString *initialsTitle);

static NSUInteger searchChecks(void) {
    __block NSUInteger failures = 0;
    void (^check)(BOOL, NSString *) = ^(BOOL ok, NSString *what) {
        if (!ok) {
            failures++;
            fprintf(stderr, "[harness] search FAIL %s\n", what.UTF8String);
        }
    };
    // Each syllable's initial, the rest kept, spaces kept.
    check([SGSearchInitials(@"번역") isEqualToString:@"ㅂㅇ"], @"번역 initials");
    check([SGSearchInitials(@"가사 설정") isEqualToString:@"ㄱㅅ ㅅㅈ"], @"가사 설정 initials");
    check([SGSearchInitials(@"Font 번역") isEqualToString:@"font ㅂㅇ"], @"latin folded, initials around it");
    // ㅂㅇ finds 번역.
    check(SGSearchWordMatches(@"ㅂㅇ", @"번역", SGSearchInitials(@"번역")), @"ㅂㅇ matches 번역");
    check(!SGSearchWordMatches(@"ㅂㅇ", @"번역", SGSearchInitials(@"가사 설정")), @"ㅂㅇ misses 가사 설정");
    // Double consonants are initials of their own.
    check([SGSearchInitials(@"꿀") isEqualToString:@"ㄲ"], @"꿀 initials ㄲ");
    check(SGSearchWordMatches(@"ㄲ", @"꿀", SGSearchInitials(@"꿀")), @"ㄲ matches 꿀");
    check(!SGSearchWordMatches(@"ㄱ", @"꿀", SGSearchInitials(@"꿀")), @"ㄱ does not match 꿀");
    // Mixed words: each word uses its own rule.
    check(SGSearchWordMatches(@"ㄱㅅ", @"가사 font", SGSearchInitials(@"가사 font")) &&
          SGSearchWordMatches(@"font", @"가사 font", SGSearchInitials(@"가사 font")), @"ㄱㅅ font mixed query");
    check(!SGSearchWordMatches(@"ㄱㅅ", @"가사 font", @"가사 font"), @"initials word does not read plain text");
    // Non-Korean queries still read the folded text, and a plain query is not an initials query.
    check(!SGSearchIsInitialsWord(@"font"), @"font is not initials");
    check(SGSearchWordMatches(@"font", @"가사 font", SGSearchInitials(@"가사 font")), @"font matches folded");
    check(!SGSearchStartsTitle(@"font", @"번역", SGSearchInitials(@"번역")), @"font does not start 번역");
    // A vowel jamo is not an initial and is read as ordinary text.
    check(!SGSearchIsInitialsWord(@"ㅏ"), @"ㅏ is not initials");
    check(SGSearchWordMatches(@"ㅏ", @"ㅏ", SGSearchInitials(@"ㅏ")), @"ㅏ is still found as typed text");
    // Ranking: initials prefix of the title's initials, and today's plain prefix.
    check(SGSearchStartsTitle(@"ㅂㅇ", @"번역", SGSearchInitials(@"번역")), @"ㅂㅇ starts 번역");
    check(SGSearchStartsTitle(@"ㄱㅅ ㅅㅈ", @"가사 설정", SGSearchInitials(@"가사 설정")), @"ㄱㅅ ㅅㅈ starts 가사 설정");
    check(SGSearchStartsTitle(@"번", @"번역", SGSearchInitials(@"번역")), @"번 starts 번역");
    check(!SGSearchStartsTitle(@"ㅂㅇ", @"가사 설정", SGSearchInitials(@"가사 설정")), @"ㅂㅇ does not start 가사 설정");
    fprintf(stderr, "[harness] search checks: %lu failure(s)\n", (unsigned long)failures);
    return failures;
}

BOOL SGHarnessWarning;

static void refactorChecks(void) {
    // The Mod page keeps its action's symbol when row decoration is shared with Settings.
    SGModPage *about = (SGModPage *)SGAboutPage();
    SGModRow *reset = nil;
    for (SGModSection *section in about.sections) {
        for (SGModRow *row in section.rows) {
            if ([row.title isEqualToString:@"Reset all settings"]) reset = row;
        }
    }
    HARNESS_CHECK([reset.symbol isEqualToString:@"trash"]);

    // A navigation controller reached through the source's parents includes itself in the search.
    UIViewController *home = [UIViewController new];
    UINavigationController *root = [[UINavigationController alloc] initWithRootViewController:home];
    SGOpenModSettings(home.view);
    HARNESS_CHECK([root.topViewController.title isEqualToString:@"Vitrine"]);

    // A deeper stack in the first child's subtree wins over a shallower later sibling.
    UIViewController *container = [UIViewController new], *wrapper = [UIViewController new];
    UINavigationController *first = [[UINavigationController alloc] initWithRootViewController:[UIViewController new]];
    UINavigationController *later = [[UINavigationController alloc] initWithRootViewController:[UIViewController new]];
    [container addChildViewController:wrapper];
    [wrapper didMoveToParentViewController:container];
    [wrapper addChildViewController:first];
    [first didMoveToParentViewController:wrapper];
    [container addChildViewController:later];
    [later didMoveToParentViewController:container];
    SGOpenModSettings(container.view);
    HARNESS_CHECK([first.topViewController.title isEqualToString:@"Vitrine"]);
    NSLog(@"[harness] refactor checks PASS");
}

static void findViews(UIView *root, Class kind, NSMutableArray *found) {
    if ([root isKindOfClass:kind]) [found addObject:root];
    for (UIView *sub in root.subviews) findViews(sub, kind, found);
}

// With `rows` on the launch line, Spotify's settings list controller and the side drawer's list by their own
// names, made before ModSettings.x's %ctor hooks them (constructor priorities hold within this binary).
static const char *const kDrawerClass = "_TtC23SideDrawer_ListPageImplP33_1D8CA7A9CC41E8D184AF8B9AAE4E684E28SideDrawerListCollectionView";
static const char *const kSettingsClass = "_TtC21Settings_PlatformImpl26SettingsListViewController";

__attribute__((constructor(101))) static void harnessClasses(void) {
    if (![NSProcessInfo.processInfo.arguments containsObject:@"rows"]) return;
    objc_registerClassPair(objc_allocateClassPair(UICollectionView.class, kDrawerClass, 0));
    objc_registerClassPair(objc_allocateClassPair(UIViewController.class, kSettingsClass, 0));
}

// The `gated` page: a switch, ten rows of filler, then a headed and noted section whose twelve rows show only
// while the switch is on, and a row that comes by itself once `later` is played.
static BOOL sg_later;
static NSString *const kGate = @"spotifyglass.harness.gate";

static UIViewController *gatedPage(void) {
    SGSetEnabled(kGate, NO);
    NSMutableArray<SGModRow *> *filler = [NSMutableArray array], *gated = [NSMutableArray array];
    for (int i = 0; i < 10; i++) [filler addObject:SGStatRow([NSString stringWithFormat:@"Filler %d", i + 1], ^NSString *{ return @"-"; })];
    for (int i = 0; i < 12; i++) {
        SGModRow *row = SGStatRow([NSString stringWithFormat:@"Gated %d", i + 1], ^NSString *{ return @"on"; });
        row.visible = ^BOOL { return SGFlag(kGate, NO); };
        [gated addObject:row];
    }
    SGModRow *later = SGStatRow(@"Came by itself", ^NSString *{ return @"later"; });
    later.visible = ^BOOL { return sg_later; };
    return [[SGModPage alloc] initWithTitle:@"Gated" intro:nil sections:@[
        SGSection(@"Gate", [@[SGOptionRow(@"Show the gated rows", nil, kGate)] arrayByAddingObjectsFromArray:filler]),
        SGNotedSection(@"Gated", gated, @"A note under the gated rows, which goes with them."),
        SGSection(@"Later", @[later]),
    ] footer:nil];
}

@interface SGInformationPresenter : UIViewController
@property (nonatomic, strong) UIAlertController *information;
@property (nonatomic) BOOL animated;
@property (nonatomic, copy) void (^completion)(void);
@end
@implementation SGInformationPresenter
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    self.information = (UIAlertController *)controller;
    self.animated = animated;
    self.completion = completion;
}
@end

static void pageStyleChecks(void) {
    SGInformationPresenter *presenter = [SGInformationPresenter new];
    SGPresentInformation(presenter, @"Information", @"Details");
    UIAlertController *alert = presenter.information;
    HARNESS_CHECK(alert.preferredStyle == UIAlertControllerStyleAlert &&
        [alert.title isEqual:@"Information"] && [alert.message isEqual:@"Details"] &&
        alert.actions.count == 1 && [alert.actions.firstObject.title isEqual:@"확인"] &&
        alert.actions.firstObject.style == UIAlertActionStyleCancel && presenter.animated && !presenter.completion);

    HARNESS_CHECK(UIContentSizeCategoryCompareToCategory(UIApplication.sharedApplication.preferredContentSizeCategory,
        UIContentSizeCategoryExtraSmall) == NSOrderedDescending);
    UIFont *capped = SGCategoryCappedFont(UIFontTextStyleBody, UIFontWeightBold, UIContentSizeCategoryExtraSmall);
    UITraitCollection *small = [UITraitCollection traitCollectionWithPreferredContentSizeCategory:UIContentSizeCategoryExtraSmall];
    HARNESS_CHECK(capped.pointSize == [UIFont preferredFontForTextStyle:UIFontTextStyleBody compatibleWithTraitCollection:small].pointSize &&
        (capped.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold));
    HARNESS_CHECK(SGCategoryCappedFont(UIFontTextStyleBody, UIFontWeightRegular, nil).pointSize ==
        [UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize);

    UITableView *table = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
    table.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    table.contentSize = CGSizeMake(320, 1000);
    table.contentInset = UIEdgeInsetsMake(20, 3, 40, 5);
    table.contentOffset = CGPointMake(0, -20);
    UIView *header = [UIView new];
    [table addSubview:header];
    [table addSubview:[UIView new]];
    SGPositionPinnedPreview(table, header, 80);
    HARNESS_CHECK(table.contentOffset.y == -80 &&
        UIEdgeInsetsEqualToEdgeInsets(table.contentInset, UIEdgeInsetsMake(80, 3, 40, 5)) &&
        UIEdgeInsetsEqualToEdgeInsets(table.verticalScrollIndicatorInsets, table.contentInset) &&
        CGRectEqualToRect(header.frame, CGRectMake(0, -80, 320, 80)) && table.subviews.lastObject == header);
    table.contentOffset = CGPointMake(0, 200);
    SGPositionPinnedPreview(table, header, 100);
    HARNESS_CHECK(table.contentOffset.y == 200 && CGRectEqualToRect(header.frame, CGRectMake(0, 200, 320, 100)));
    NSLog(@"[harness] page style checks PASS");
}

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UINavigationController *nav;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    if ([NSProcessInfo.processInfo.arguments containsObject:@"page-style-check"]) {
        pageStyleChecks();
        exit(0);
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"font-check"]) {
        UIFont *base = [UIFont systemFontOfSize:23.5 weight:UIFontWeightSemibold];
        UIFont *font = SGMonospacedDigitsFont(base);
        NSArray *features = [font.fontDescriptor objectForKey:UIFontDescriptorFeatureSettingsAttribute];
        HARNESS_CHECK(([features containsObject:@{
            UIFontFeatureTypeIdentifierKey: @(kNumberSpacingType),
            UIFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector)
        }]));
        HARNESS_CHECK(font.pointSize == 23.5);
        HARNESS_CHECK(SGMonospacedDigitsFont(nil) == nil);
        NSLog(@"[harness] tabular font checks PASS");
        exit(0);
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"refactor-check"]) {
        refactorChecks();
        exit(0);
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"search"]) {
        NSUInteger failures = searchChecks();
        NSLog(@"[harness] search %@", failures ? @"failed" : @"passed");
        exit(failures ? 1 : 0);
    }
    NSLog(@"[harness] page protocol %@", NSStringFromProtocol(@protocol(SPTPageController)));
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    if (![args containsObject:@"keep"]) {
        SGSetEnabled(SGKeyRedesign, NO);
        SGSetEnabled(SGKeyRedesignUntested, NO);
    }
    NSMutableArray<NSString *> *actions = [NSMutableArray array];
    for (NSString *arg in [args subarrayWithRange:NSMakeRange(1, args.count - 1)]) {
        if ([arg isEqualToString:@"redesign"]) SGSetEnabled(SGKeyRedesign, YES);
        else if ([arg isEqualToString:@"warning"]) SGHarnessWarning = YES;
        else if (![arg isEqualToString:@"keep"]) [actions addObject:arg];
    }

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UIViewController *home = [UIViewController new];
    home.view.backgroundColor = UIColor.blackColor;
    self.nav = [[UINavigationController alloc] initWithRootViewController:home];
    self.window.rootViewController = self.nav;
    [self.window makeKeyAndVisible];
    if ([args containsObject:@"information-check"]) {
        extern void SGCheckInformationAlerts(void);
        dispatch_async(dispatch_get_main_queue(), ^{ SGCheckInformationAlerts(); });
        return YES;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ SGOpenModSettings(home.view); });

    [actions enumerateObjectsUsingBlock:^(NSString *action, NSUInteger i, BOOL *stop) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((1 + 0.9 * i) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"[harness] %@", action);
            [self run:action];
        });
    }];
    return YES;
}

- (UITableView *)table {
    return ((UITableViewController *)self.nav.topViewController).tableView;
}

- (NSIndexPath *)pathFrom:(NSString *)text {
    NSArray<NSString *> *at = [text componentsSeparatedByString:@"."];
    return [NSIndexPath indexPathForRow:at[1].integerValue inSection:at[0].integerValue];
}

- (void)run:(NSString *)action {
    NSArray<NSString *> *parts = [action componentsSeparatedByString:@"="];
    NSString *verb = parts.firstObject, *value = parts.count > 1 ? parts[1] : @"";
    UITableView *table = self.table;
    if ([verb isEqualToString:@"toggle"]) {
        NSMutableArray<UIControl *> *controls = [NSMutableArray array];
        findViews([table cellForRowAtIndexPath:[self pathFrom:value]].accessoryView, UIControl.class, controls);
        UIControl *toggle = nil;
        for (UIControl *control in controls) if ([control respondsToSelector:@selector(setOn:animated:)]) toggle = control;
        if (!toggle) { NSLog(@"[harness] no switch at %@", value); return; }
        [(id)toggle setOn:![(id)toggle isOn] animated:YES];
        [toggle sendActionsForControlEvents:UIControlEventValueChanged];
    } else if ([verb isEqualToString:@"cancel"]) {
        UIAlertController *alert = (UIAlertController *)self.nav.presentedViewController;
        if (![alert isKindOfClass:UIAlertController.class]) return;
        NSLog(@"[harness] alert \"%@\": %@", alert.title, alert.message);
        [alert dismissViewControllerAnimated:YES completion:nil];
    } else if ([verb isEqualToString:@"bottom"]) {
        [table setContentOffset:CGPointMake(0, MAX(-table.adjustedContentInset.top, table.contentSize.height - table.bounds.size.height + table.adjustedContentInset.bottom)) animated:NO];
    } else if ([verb isEqualToString:@"gated"]) {
        [self.nav pushViewController:gatedPage() animated:NO];
    } else if ([verb isEqualToString:@"rows"]) {
        // The row ModSettings.x adds to Spotify's settings list and to the side drawer's list, each emptied of its
        // subviews afterward as Spotify can do, then laid out again.
        NSUInteger (^count)(UIView *) = ^NSUInteger(UIView *list) {
            NSUInteger n = 0;
            for (UIView *sub in list.subviews) n += [NSStringFromClass(sub.class) isEqualToString:@"SGModSettingsRow"];
            return n;
        };
        void (^empty)(UIView *) = ^(UIView *list) {
            for (UIView *sub in [list.subviews copy]) [sub removeFromSuperview];
            [list setNeedsLayout];
            [list layoutIfNeeded];
        };
        UICollectionView *drawer = [[NSClassFromString(@(kDrawerClass)) alloc] initWithFrame:CGRectMake(0, 0, 390, 600)
                                                                         collectionViewLayout:[UICollectionViewFlowLayout new]];
        [self.window addSubview:drawer];
        [drawer layoutIfNeeded];
        NSUInteger drawerFirst = count(drawer);
        empty(drawer);
        UIViewController *settings = [NSClassFromString(@(kSettingsClass)) new];
        UICollectionView *list = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 0, 390, 600) collectionViewLayout:[UICollectionViewFlowLayout new]];
        [settings.view addSubview:list];
        [settings viewDidLayoutSubviews];
        [list layoutIfNeeded];
        NSUInteger settingsFirst = count(list);
        empty(list);
        NSLog(@"[harness] rows: drawer %lu on its first layout, %lu after it was emptied; settings %lu, %lu after it was emptied",
              (unsigned long)drawerFirst, (unsigned long)count(drawer), (unsigned long)settingsFirst, (unsigned long)count(list));
        [drawer removeFromSuperview];
    } else if ([verb isEqualToString:@"needs"]) {
        [self.nav pushViewController:[[SGModPage alloc] initWithTitle:@"Lock screen" intro:nil sections:@[
            SGSection(@"Lock screen artwork", @[SGLockScreenArtworkNeedsRow()]),
        ] footer:nil] animated:NO];
    } else if ([verb isEqualToString:@"tap"]) {
        NSIndexPath *path = [self pathFrom:value];
        [table.delegate tableView:table didSelectRowAtIndexPath:path];
        UIAlertController *alert = (UIAlertController *)self.nav.presentedViewController;
        if ([alert isKindOfClass:UIAlertController.class]) NSLog(@"[harness] alert \"%@\": %@", alert.title, alert.message);
    } else if ([verb isEqualToString:@"top"]) {
        [table setContentOffset:CGPointMake(0, -table.adjustedContentInset.top) animated:NO];
    } else if ([verb isEqualToString:@"later"]) {
        sg_later = YES;
    } else if ([verb isEqualToString:@"layout"]) {
        UIEdgeInsets inset = table.adjustedContentInset;
        NSLog(@"[harness] offset %.0f of room %.0f", table.contentOffset.y + inset.top, table.bounds.size.height - inset.top - inset.bottom);
        for (NSInteger section = 0; section < table.numberOfSections; section++) {
            NSLog(@"[harness] section %ld: %ld rows, heading %.0f pt, note %.0f pt", (long)section, (long)[table numberOfRowsInSection:section],
                  [table rectForHeaderInSection:section].size.height, [table rectForFooterInSection:section].size.height);
        }
    } else if ([verb isEqualToString:@"dump"]) {
        NSLog(@"[harness] Redesigned UI stored %d", SGRedesignedUIStored());
        for (NSInteger section = 0; section < table.numberOfSections; section++) {
            NSMutableArray<NSString *> *rows = [NSMutableArray array];
            for (NSInteger row = 0; row < [table numberOfRowsInSection:section]; row++) {
                NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:section];
                UITableViewCell *cell = [table.dataSource tableView:table cellForRowAtIndexPath:path];
                NSMutableArray<UILabel *> *labels = [NSMutableArray array];
                findViews(cell.accessoryView, UILabel.class, labels);
                NSString *text = [(UIListContentConfiguration *)cell.contentConfiguration text];
                [rows addObject:labels.count ? [NSString stringWithFormat:@"%@ [%@]", text, labels.firstObject.text] : text];
            }
            NSLog(@"[harness] section %ld: %@", (long)section, [rows componentsJoinedByString:@", "]);
        }
    }
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
