// Podcasts and audiobooks on Home. HomeHeader.x's Logos output is included, so the filter menu and the way back from a hidden
// filter are driven over Spotify's chips as recorded on a device (Home_PillUIKit pills with the identifiers
// home-feed-default, home-feed-music-chip, home-feed-podcasts-chip).
#import <UIKit/UIKit.h>
#import "harness-fail.h"
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Home.h"

#include "HomeHeader.gen.m"

#pragma mark - helpers

static NSUInteger sg_checks;
#define CHECK(condition) do { sg_checks++; HARNESS_CHECK(condition); } while (0)

static NSUserDefaults *defaults(void) { return NSUserDefaults.standardUserDefaults; }

static void spin(NSTimeInterval seconds) {
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static void setHidePodcasts(BOOL hidden) {
    [defaults() setBool:hidden forKey:SGRKeyHomeHidePodcasts];
    SGPrefsChanged();
    spin(0.3);
}

#pragma mark - Home

static UIControl *makeChip(NSString *identifier, NSString *label, NSUInteger *fired) {
    UIControl *chip = [UIControl new];
    chip.accessibilityIdentifier = identifier;
    chip.accessibilityLabel = label;
    if (fired) [chip addAction:[UIAction actionWithHandler:^(UIAction *action) { (*fired)++; }] forControlEvents:UIControlEventPrimaryActionTriggered];
    return chip;
}

static NSArray<NSString *> *menuTitles(void) {
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    UIMenu *filters = (UIMenu *)menuElements().firstObject;
    for (UIAction *action in filters.children) [titles addObject:action.title];
    return titles;
}

// The page holds its stack weakly (sg_stack).
static UIStackView *sg_heldStack;
static NSUInteger sg_defaultFired, sg_musicFired, sg_podcastsFired, sg_audiobooksFired;

// Spotify's chips in their order: All, Music, Podcasts, and an Audiobooks one where the region has it.
static UIStackView *chipStack(void) {
    sg_defaultFired = sg_musicFired = sg_podcastsFired = sg_audiobooksFired = 0;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        makeChip(@"home-feed-default", @"전체", &sg_defaultFired),
        makeChip(@"home-feed-music-chip", @"음악", &sg_musicFired),
        makeChip(@"home-feed-podcasts-chip", @"팟캐스트", &sg_podcastsFired),
        makeChip(@"home-feed-audiobooks-chip", @"오디오북", &sg_audiobooksFired),
    ]];
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.frame = CGRectMake(0, 0, 400, 34);
    [stack layoutIfNeeded];
    sg_stack = sg_heldStack = stack;
    return stack;
}

static void checkMenu(void) {
    chipStack();
    setHidePodcasts(NO);
    NSArray<NSString *> *all = @[@"전체", @"음악", @"팟캐스트", @"오디오북"];
    CHECK([menuTitles() isEqualToArray:all]);
    setHidePodcasts(YES);
    CHECK([menuTitles() isEqualToArray:(@[@"전체", @"음악"])]);
    setHidePodcasts(NO);
    CHECK([menuTitles() isEqualToArray:all]);
}

static void checkLeaving(void) {
    UIStackView *stack = chipStack();
    UIControl *defaultChip = stack.arrangedSubviews[0], *music = stack.arrangedSubviews[1], *podcasts = stack.arrangedSubviews[2];
    setHidePodcasts(NO);
    // Shown: a chosen Podcasts chip is left alone.
    defaultChip.selected = NO;
    podcasts.selected = YES;
    syncPodcastChips(stack);
    spin(0.1);
    CHECK(sg_defaultFired == 0);

    // Hidden, and chosen: back to the default chip on the next turn, not this one, and once.
    [defaults() setBool:YES forKey:SGRKeyHomeHidePodcasts];
    SGPrefsChanged();
    syncPodcastChips(stack);
    CHECK(sg_defaultFired == 0);
    spin(0.1);
    CHECK(sg_defaultFired == 1);
    syncPodcastChips(stack);
    spin(0.1);
    CHECK(sg_defaultFired == 1);
    CHECK(sg_musicFired == 0 && sg_podcastsFired == 0);

    // Home followed: another chip chosen is left alone.
    podcasts.selected = NO;
    defaultChip.selected = NO;
    music.selected = YES;
    syncPodcastChips(stack);
    spin(0.1);
    CHECK(sg_defaultFired == 1);

    // Chosen again later, the way back is asked again.
    music.selected = NO;
    podcasts.selected = YES;
    syncPodcastChips(stack);
    spin(0.1);
    CHECK(sg_defaultFired == 2);
    podcasts.selected = NO;
    setHidePodcasts(NO);
}

// The switch flipped on while Home is on Podcasts: the observer takes Home off it, with no layout pass of the page.
static void checkLive(void) {
    UIStackView *stack = chipStack();
    setHidePodcasts(NO);
    ((UIControl *)stack.arrangedSubviews[2]).selected = YES;
    spin(0.1);
    CHECK(sg_defaultFired == 0);
    setHidePodcasts(YES);
    CHECK(sg_defaultFired == 1);
    ((UIControl *)stack.arrangedSubviews[2]).selected = NO;
    setHidePodcasts(NO);
}

static void run(void) {
    checkMenu();
    checkLeaving();
    checkLive();
    [defaults() removeObjectForKey:SGRKeyHomeHidePodcasts];
    printf("[harness] home-podcasts: %lu checks passed\n", (unsigned long)sg_checks);
    fflush(stdout);
    exit(0);
}

@interface HomePodcastsApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation HomePodcastsApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    self.window.rootViewController = [UIViewController new];
    // A timer, not a block of the main queue: the checks run the run loop, which would not run the main queue's other blocks from inside one.
    [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:NO block:^(NSTimer *timer) { run(); }];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(HomePodcastsApp.class));
    }
}
