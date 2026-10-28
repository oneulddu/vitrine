// The live preview cards of the redesign's page settings (Redesigned/Kit/SGRPagePreview.m), on the pages the real
// builders make (PlaylistSettings.m, HomeSettings.m, SearchSettings.m, AlbumSettings.m, ArtistSettings.m), under real
// UIKit in an iOS simulator (build.sh). Each card is drawn in its default state, then the page's settings are changed while it is
// on screen and it is drawn again; then with a light and a dark accent color, and at a large text size. Each state's
// card is written to build/png/<page>-<state>.png, and the default page whole to build/png/<page>-page.png.
//
// Checked: what VoiceOver reads off each card in each state (the parts shown, by name), that a change while the card
// is in sight animates and one while it is scrolled out of sight is left undrawn until the card is back in sight,
// then drawn at once, that a part a switch brings back below the card's foot is scrolled into sight
// (<page>-revealed.png), that Home's page color goes with the Top picks colors (home-no-colour.png) and the artist's
// field with the photo shown, and that the card grows with the text.
// Exits nonzero on the first failure (harness-fail.h).
#import <UIKit/UIKit.h>
#import "../harness-fail.h"
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "Redesigned/Kit/SGRPagePreview.h"
#import "Redesigned/Kit/SGRHeaderInfo.h"
#import "Redesigned/Playlist/Playlist.h"
#import "Redesigned/Home/Home.h"
#import "Redesigned/Search/Search.h"
#import "Redesigned/Album/Album.h"
#import "Redesigned/Album/AlbumNotes.h"
#import "Redesigned/Artist/Artist.h"

static NSString *outDir;
static UIWindow *window;
static UINavigationController *nav;

static void spin(NSTimeInterval seconds) {
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

// Every setting of the mod's gone, as on a fresh install, then the shelves Home has seen lately.
static void reset(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    for (NSString *key in store.dictionaryRepresentation.allKeys) {
        if ([key hasPrefix:@"spotifyglass."]) [store removeObjectForKey:key];
    }
    NSDate *now = NSDate.date;
    NSArray<NSString *> *seen = @[@"Recents", @"Made For You", @"Jump back in"];
    NSMutableDictionary *table = [NSMutableDictionary dictionary];
    [seen enumerateObjectsUsingBlock:^(NSString *identity, NSUInteger i, BOOL *stop) {
        table[identity] = @{@"first": [now dateByAddingTimeInterval:-86400.0 * (3 - i)], @"last": now};
    }];
    [store setObject:table forKey:SGRKeyHomeShelvesSeen];
    SGPrefsChanged();
}

static SGRPagePreview *cardIn(UIView *view) {
    if ([view isKindOfClass:SGRPagePreview.class]) return (SGRPagePreview *)view;
    for (UIView *sub in view.subviews) {
        SGRPagePreview *card = cardIn(sub);
        if (card) return card;
    }
    return nil;
}

static UITableView *tableOf(UIViewController *page) {
    return ((UITableViewController *)page).tableView;
}

static SGRPagePreview *show(UIViewController *(^builder)(void)) {
    UIViewController *page = builder();
    nav.viewControllers = @[page];
    [nav.view layoutIfNeeded];
    [page.view layoutIfNeeded];
    spin(0.4);
    SGRPagePreview *card = cardIn(tableOf(page).tableHeaderView);
    if (!card) HARNESS_FAIL(@"no preview card on %@", page.title);
    if (card.bounds.size.height < 1) HARNESS_FAIL(@"the card on %@ has no height", page.title);
    return card;
}

static BOOL animating(UIView *view) {
    if (view.layer.animationKeys.count) return YES;
    for (UIView *sub in view.subviews) if (animating(sub)) return YES;
    return NO;
}

static void writePNG(UIView *view, NSString *name) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:view.bounds];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:YES];
    }];
    NSString *path = [outDir stringByAppendingPathComponent:[name stringByAppendingString:@".png"]];
    if (![UIImagePNGRepresentation(image) writeToFile:path atomically:YES]) HARNESS_FAIL(@"could not write %@", path);
    printf("wrote %s\n", path.UTF8String);
}

static void expectValue(SGRPagePreview *card, NSString *expected, NSString *state) {
    if (![card.accessibilityValue isEqualToString:expected]) {
        HARNESS_FAIL(@"%@: VoiceOver reads \"%@\", expected \"%@\"", state, card.accessibilityValue, expected);
    }
    printf("PASS %s reads \"%s\"\n", state.UTF8String, expected.UTF8String);
}

// One page: `defaults` and `changed` are what VoiceOver reads off its card before and after `change`.
static void runPage(NSString *name, UIViewController *(^builder)(void), NSString *defaults, void (^change)(void), NSString *changed) {
    reset();
    SGRPagePreview *card = show(builder);
    expectValue(card, defaults, [name stringByAppendingString:@" default"]);
    writePNG(card, [name stringByAppendingString:@"-default"]);
    writePNG(nav.view, [name stringByAppendingString:@"-page"]);

    // Changed on screen: the card moves to it, over the layout motion.
    change();
    spin(0.05);
    if (!animating(card)) HARNESS_FAIL(@"%@: a change in sight drew at once", name);
    printf("PASS %s change in sight animates\n", name.UTF8String);
    spin(1.0);
    expectValue(card, changed, [name stringByAppendingString:@" changed"]);
    writePNG(card, [name stringByAppendingString:@"-changed"]);

    // The defaults again, with the card scrolled out of sight: left undrawn until it is back in sight, then drawn at
    // once. Room under the rows (the page's insets are its own), so a short page scrolls its header away too.
    UITableView *table = tableOf(nav.topViewController);
    table.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, window.bounds.size.height)];
    [window layoutIfNeeded];
    [table setContentOffset:CGPointMake(0, CGRectGetMaxY(table.tableHeaderView.frame)) animated:NO];
    [window layoutIfNeeded];
    if (CGRectIntersectsRect([card convertRect:card.bounds toView:nil], window.bounds)) {
        HARNESS_FAIL(@"%@: the card did not scroll away (%@ at offset %.0f)", name, NSStringFromCGRect([card convertRect:card.bounds toView:nil]), table.contentOffset.y);
    }
    reset();
    spin(0.05);
    if (animating(card)) HARNESS_FAIL(@"%@: a change out of sight animated", name);
    expectValue(card, changed, [name stringByAppendingString:@" undrawn out of sight"]);
    [table setContentOffset:CGPointMake(0, -table.adjustedContentInset.top) animated:NO];
    [window layoutIfNeeded];
    spin(0.05);
    if (animating(card)) HARNESS_FAIL(@"%@: a change made out of sight animated as the card came back", name);
    expectValue(card, defaults, [name stringByAppendingString:@" back in sight"]);
}

// Home's page color goes with the Top picks cards' colors (HomeTopPicks.x clears both).
static void runHomeTint(void) {
    reset();
    SGRPagePreview *card = show(^UIViewController *{ return SGRHomeSettingsPage(); });
    if (!card.topTint) HARNESS_FAIL(@"home: no page color with the cards' colors on");
    SGSetEnabled(SGRKeyHomeTopPicksColour, NO);
    spin(1.0);
    if (card.topTint) HARNESS_FAIL(@"home: the page color stayed with the cards' colors off");
    printf("PASS home page color goes with the cards' colors\n");
    writePNG(card, @"home-no-colour");
}

// The artist's page takes its field from the photo shown, Apple Music's too (ArtistHeader.x).
static void runArtistField(void) {
    reset();
    SGRPagePreview *card = show(^UIViewController *{ return SGRArtistSettingsPage(); });
    UIColor *spotify = card.fieldColor;
    SGSetEnabled(SGRKeyArtistApplePhoto, YES);
    spin(1.0);
    if ([card.fieldColor isEqual:spotify]) HARNESS_FAIL(@"artist: the field kept Spotify's photo's color under Apple Music's");
    printf("PASS artist field follows the photo\n");
}

static UIView *partNamed(UIView *view, NSString *name) {
    if ([view.accessibilityLabel isEqualToString:name] && ![view isKindOfClass:SGRPagePreview.class]) return view;
    for (UIView *sub in view.subviews) {
        UIView *found = partNamed(sub, name);
        if (found) return found;
    }
    return nil;
}

// One switch for a part below the card's foot: the mock scrolls to it.
static void runReveal(NSString *name, UIViewController *(^builder)(void), void (^change)(void), NSString *part) {
    reset();
    SGRPagePreview *card = show(builder);
    change();
    spin(1.0);
    UIView *view = partNamed(card, part);
    if (!view) HARNESS_FAIL(@"%@: no part named %@ shows", name, part);
    CGFloat top = CGRectGetMinY([view convertRect:view.bounds toView:card]);
    if (top < 0 || top >= card.bounds.size.height) HARNESS_FAIL(@"%@: %@ is out of the card's sight (top at %.0f)", name, part, top);
    printf("PASS %s scrolls to %s\n", name.UTF8String, part.UTF8String);
    writePNG(card, [name stringByAppendingString:@"-revealed"]);
}

// The accent colors, light and dark, picked on the Appearance page while this one is away; and a large text size,
// which the card grows with.
static void runLooks(NSString *name, UIViewController *(^builder)(void)) {
    reset();
    CGFloat height = show(builder).bounds.size.height;
    NSDictionary<NSString *, NSNumber *> *accents = @{@"accent-light": @0xFFD60A, @"accent-dark": @0x2A1B6E};
    for (NSString *accent in accents) {
        reset();
        SGSetInt(SGRKeyAccent, accents[accent].integerValue);
        writePNG(show(builder), [NSString stringWithFormat:@"%@-%@", name, accent]);
    }
    reset();
    window.traitOverrides.preferredContentSizeCategory = UIContentSizeCategoryAccessibilityExtraLarge;
    SGRPagePreview *large = show(builder);
    if (large.bounds.size.height <= height) HARNESS_FAIL(@"%@: the card did not grow with the text (%.0f, %.0f)", name, height, large.bounds.size.height);
    printf("PASS %s card grows with the text (%.0f to %.0f pt)\n", name.UTF8String, height, large.bounds.size.height);
    writePNG(large, [name stringByAppendingString:@"-large-text"]);
    [window.traitOverrides removeTrait:UITraitPreferredContentSizeCategory.class];
}

static UIView *identified(UIView *view, NSString *identifier) {
    if ([view.accessibilityIdentifier isEqual:identifier]) return view;
    for (UIView *child in view.subviews) {
        UIView *found = identified(child, identifier);
        if (found) return found;
    }
    return nil;
}

static BOOL visibleText(UIView *view, NSString *text) {
    if (view.hidden || view.alpha < 0.01) return NO;
    if ([view isKindOfClass:UILabel.class] && [((UILabel *)view).text isEqual:text]) return YES;
    for (UIView *child in view.subviews) if (visibleText(child, text)) return YES;
    return NO;
}

static void runCoverChoices(void) {
    reset();
    for (int album = 0; album < 2; album++) for (int playlist = 0; playlist < 2; playlist++) {
        SGSetInt(SGRKeyAlbumFullCover, album);
        SGSetInt(SGRKeyPlaylistFullCover, playlist);
        for (NSNumber *isAlbum in @[@YES, @NO]) {
            SGRPagePreview *card = show(^UIViewController *{
                return isAlbum.boolValue ? SGRAlbumSettingsPage() : SGRPlaylistSettingsPage();
            });
            UIView *art = identified(card, @"vitrine.preview.header.artwork");
            BOOL full = isAlbum.boolValue ? album : playlist;
            if (!art || art.bounds.size.width <= 0) HARNESS_FAIL(@"missing cover preview");
            if (full && CGRectGetMinX(art.frame) != 0) HARNESS_FAIL(@"Full screen cover must reach both edges");
            if (!full && (CGRectGetMinX(art.frame) <= 0 || fabs(art.bounds.size.width - art.bounds.size.height) > 0.5))
                HARNESS_FAIL(@"Card cover must remain an inset square");
            // Change the other page while this card stays visible: no effect on its cover.
            CGRect before = art.frame;
            SGSetInt(isAlbum.boolValue ? SGRKeyPlaylistFullCover : SGRKeyAlbumFullCover, !full);
            spin(0.4);
            if (!CGRectEqualToRect(before, art.frame)) HARNESS_FAIL(@"other page's cover setting leaked");
            SGSetInt(SGRKeyAlbumFullCover, album); SGSetInt(SGRKeyPlaylistFullCover, playlist);
        }
    }
    reset();
    SGRPagePreview *card = show(^UIViewController *{ return SGRAlbumSettingsPage(); });
    if (!visibleText(card, @"Your plays: 12")) HARNESS_FAIL(@"personal counts remain the default");
    SGSetInt(SGRKeyAlbumPlayCountsSource, 1);
    spin(0.4);
    if (!visibleText(card, @"Spotify plays: 12")) HARNESS_FAIL(@"row preview must name Spotify source");
    SGSetInt(SGRKeyAlbumPlayCountsPlace, SGRAlbumPlayCountsInMenu);
    spin(0.4);
    if (!visibleText(card, @"Spotify plays: 12")) HARNESS_FAIL(@"menu preview must name Spotify source");
    SGSetInt(SGRKeyAlbumPlayCountsSource, 0);
    spin(0.4);
    if (!visibleText(card, @"Your plays: 12")) HARNESS_FAIL(@"menu preview must restore personal source");
    printf("PASS four cover combinations and both count sources in row/menu previews\n");
}

static void runChecks(void) {
    runCoverChoices();
    runPage(@"playlist", ^UIViewController *{ return SGRPlaylistSettingsPage(); },
            @"Open cover on tap and Sort and Mix",
            ^{
                SGSetEnabled(SGRKeyPlaylistCoverViewer, NO);
                SGSetEnabled(SGRKeyPlaylistHideCuration, NO);
                SGSetEnabled(SGRKeyPlaylistMenuSortMix, NO);
            }, @"Curation pills");

    runPage(@"search", ^UIViewController *{ return SGRSearchSettingsPage(); },
            @"Tinted glass",
            ^{
                SGSetEnabled(SGRKeySearchHideWatchFeeds, NO);
                SGSetEnabled(SGRKeySearchHideOther, NO);
                SGSetEnabled(SGRKeySearchGlassCards, NO);
            }, @"Everything else, Video carousels, and Category cards");

    runPage(@"home", ^UIViewController *{ return SGRHomeSettingsPage(); },
            @"Home look, Top picks, Shortcuts, DJ, Made For You, and Jump back in",
            ^{
                SGSetEnabled(SGRKeyHomeTopPicksHeading, YES);
                SGSetEnabled(SGRKeyHomeKeepTitle, YES);
                SGSetEnabled(SGRKeyHomeHideDJ, YES);
                SGSetEnabled(SGRKeyHomeSongSuggestions, YES);
                SGSetEnabled(SGRKeyHomePreviews, YES);
                SGSetEnabled(SGRHomeShelfHideKey(@"Made For You"), YES);
                [NSUserDefaults.standardUserDefaults setObject:@"Jump back in" forKey:SGRKeyHomeTopPicksFrom];
            }, @"Home look and Title stays on scroll, Top picks, Shortcuts, Song suggestions, Video and playlist previews, and Recents");
    // Without the Home look: no Top picks, Spotify's tiles and title, the first shelf back in its place.
    runPage(@"home-plain", ^UIViewController *{ return SGRHomeSettingsPage(); },
            @"Home look, Top picks, Shortcuts, DJ, Made For You, and Jump back in",
            ^{ SGSetEnabled(SGRKeyHomeLook, NO); },
            @"Shortcuts, DJ, Recents, Made For You, and Jump back in");

    runPage(@"album", ^UIViewController *{ return SGRAlbumSettingsPage(); },
            @"Animated covers, Play counts, and Album notes",
            ^{
                SGSetEnabled(SGRKeyAlbumMotion, NO);
                SGSetInt(SGRKeyAlbumNotesPlace, SGRAlbumNotesUnderPlay);
                SGSetInt(SGRKeyAlbumPlayCountsPlace, SGRAlbumPlayCountsInMenu);
                SGSetEnabled(SGRKeyAlbumHideTrackArtists, NO);
                SGSetEnabled(SGRKeyAlbumHideMoreBy, NO);
                SGSetEnabled(SGRKeyAlbumHideVideos, NO);
            }, @"Album notes, More by the artist, Related music videos, and Play counts");

    runPage(@"artist", ^UIViewController *{ return SGRArtistSettingsPage(); },
            @"Artist logos and Animated artist artwork, Release countdown, Artist pick, and About",
            ^{
                SGSetEnabled(SGRKeyArtistLogo, NO);
                SGSetEnabled(SGRKeyArtistMotion, NO);
                SGSetEnabled(SGRKeyArtistApplePhoto, YES);
                SGSetEnabled(SGRKeyArtistHideVideos, NO);
                SGSetEnabled(SGRKeyArtistHideTabs, NO);
                SGSetEnabled(SGRKeyArtistHidePick, YES);
                SGSetEnabled(SGRKeyArtistHideCountdown, YES);
            }, @"Apple Music artist photo, Music, Video and Merch tabs, Videos, and About");

    runHomeTint();
    runArtistField();
    runReveal(@"home",^UIViewController *{ return SGRHomeSettingsPage(); }, ^{ SGSetEnabled(SGRKeyHomePreviews, YES); },
              @"Video and playlist previews");
    runReveal(@"album", ^UIViewController *{ return SGRAlbumSettingsPage(); }, ^{ SGSetEnabled(SGRKeyAlbumHideMerch, NO); }, @"Merch");
    runReveal(@"artist", ^UIViewController *{ return SGRArtistSettingsPage(); }, ^{ SGSetEnabled(SGRKeyArtistHideVideos, NO); }, @"Videos");

    runLooks(@"playlist", ^UIViewController *{ return SGRPlaylistSettingsPage(); });
    runLooks(@"search", ^UIViewController *{ return SGRSearchSettingsPage(); });
    runLooks(@"home", ^UIViewController *{ return SGRHomeSettingsPage(); });
    runLooks(@"album", ^UIViewController *{ return SGRAlbumSettingsPage(); });
    runLooks(@"artist", ^UIViewController *{ return SGRArtistSettingsPage(); });

    [NSUserDefaults.standardUserDefaults removePersistentDomainForName:NSBundle.mainBundle.bundleIdentifier];
    printf("page previews: all checks passed\n");
    fflush(stdout);
    exit(0);
}

@interface HarnessApp : UIResponder <UIApplicationDelegate>
@end

@implementation HarnessApp
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        fputs("[harness] FAIL the checks timed out\n", stderr);
        exit(1);
    });
    return YES;
}
@end

@interface HarnessScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation HarnessScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    window = [[UIWindow alloc] initWithWindowScene:windowScene];
    window.frame = windowScene.coordinateSpace.bounds;
    window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    nav = [UINavigationController new];
    window.rootViewController = nav;
    [window makeKeyAndVisible];
    self.window = window;
    // From a timer, not the main queue: the checks spin the run loop, and the main queue runs none of the cards'
    // blocks while one of its own is running.
    [NSTimer scheduledTimerWithTimeInterval:0 repeats:NO block:^(NSTimer *timer) { runChecks(); }];
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        outDir = [NSString stringWithUTF8String:getenv("PAGE_PREVIEWS_PNG") ?: "png"];
        [NSFileManager.defaultManager createDirectoryAtPath:outDir withIntermediateDirectories:YES attributes:nil error:NULL];
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(HarnessApp.class));
    }
}
