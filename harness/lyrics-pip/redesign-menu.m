#import "tests.h"
#import "../../tweak/Sources/Redesigned/Player/PlayerMenu.m"

static SGRMenuItems menuItems;
static SGRMenuKind menuKind;
void SGRSystemMenuWatch(UIView *button, SGRMenuItems items, SGRMenuKind kind) {
    menuItems = [items copy]; menuKind = [kind copy];
}
UIAction *SGRLyricsSearchAction(NSString *track) {
    return [UIAction actionWithTitle:@"Search Lyrics" image:nil identifier:nil handler:^(UIAction *action) {}];
}
// LyricsStyle.m and PlayerQueue.m: the lyrics style submenu and Playing Next, whose own items are not under test.
UIMenu *SGRLyricsStyleMenu(NSString *title) { return [UIMenu menuWithTitle:title children:@[]]; }
void SGRPlayerShowQueue(UIView *from) {}
// Source selection is covered by lyrics-walk; keep the real menu entry in this integration check.
BOOL SGLyricsEnabled(void) { return YES; }
void SGLyricsAskOffers(NSString *track) {}
NSDictionary *SGLyricsOffersSoFar(NSString *track, NSArray **asking) { if (asking) *asking = @[]; return @{}; }
NSString *SGLyricsChosenSource(NSString *track) { return nil; }
void SGLyricsChooseSource(NSString *track, NSString *key) {}
void SGLyricsChooseAutomatic(NSString *track) {}
NSArray *SGLyricsOrder(void) { return @[]; }
SGLyricsProvider *SGLyricsProviderFor(NSString *key) { return nil; }
NSNotificationName const SGLyricsOffersDidChangeNotification = @"harness.offers";
void SGPresentPopover(UIViewController *panel, UIView *from) {}
SGRPlayerBackgroundKind SGRPlayerBackground(void) { return SGRPlayerBackgroundFluid; }
void SGRPlayerMenuSetBackground(SGRPlayerBackgroundKind kind) {}

static void tap(UIAction *action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button addAction:action forControlEvents:UIControlEventTouchUpInside];
    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
}
void SGTestRedesignMenu(void) {
    UIView *source = SGTestSourceView();
    SGRPlayerMenuWatch(source);
    SGTestPiPState(NO, NO, NO);
    NSArray *items = menuItems();
    // Sound, PiP, Playing Next, Search Lyrics, Lyrics Style, then the two backgrounds the player is not showing.
    SGTestAssert(items.count == 8 && [((UIAction *)items.lastObject).title isEqual:@"Lyrics Source"] && [((UIAction *)items[0]).title isEqual:@"Speed, Pitch & Reverb"]
        && [((UIAction *)items[2]).title isEqual:@"Playing Next"]
        && [((UIAction *)items[3]).title isEqual:@"Search Lyrics"] && [items[4] isKindOfClass:UIMenu.class]
        && [menuKind() isEqual:@"track"],
        @"redesign preserves sound, queue, lyric search, lyric style and alternate artwork items");
    UIAction *pip = items[1];
    SGTestAssert([pip.title isEqual:@"Open lyrics Picture in Picture"] && !(pip.attributes & UIMenuElementAttributesDisabled),
        @"redesign exposes enabled action even when launch flag is off");
    NSUInteger alerts = SGTestDisabledAlerts();
    tap(pip);
    SGTestAssert(SGTestDisabledAlerts() == alerts + 1, @"redesign disabled entry explains activation");
    SGTestPiPState(YES, NO, NO);
    tap(menuItems()[1]);
    SGTestAssert(SGLyricsPiPStarting(), @"redesign open invokes user-started shared engine");
    pip = menuItems()[1];
    SGTestAssert([pip.title isEqual:@"Close lyrics Picture in Picture"], @"redesign rebuild labels pending start as close");
    tap(pip);
    SGTestAssert(!SGLyricsPiPStarting(), @"redesign close cancels starting session");
    SGTestPiPState(YES, YES, NO);
    SGTestAssert([((UIAction *)menuItems()[1]).title isEqual:@"Close lyrics Picture in Picture"], @"redesign active entry is close");
    SGTestSetTrack(@"spotify:episode:episode", nil);
    SGTestAssert(menuItems().count == 5 && [menuKind() isEqual:@"episode"], @"podcast keeps PiP and Playing Next, and still excludes lyric search and style");
    SGTestPiPState(NO, NO, NO);
}
