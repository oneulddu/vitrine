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
    SGTestAssert(items.count == 5 && [((UIAction *)items[0]).title isEqual:@"Speed, Pitch & Reverb"]
        && [((UIAction *)items[2]).title isEqual:@"Search Lyrics"] && [menuKind() isEqual:@"track"],
        @"redesign preserves sound, lyric search and alternate artwork items");
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
    SGTestAssert(menuItems().count == 4 && [menuKind() isEqual:@"episode"], @"podcast keeps PiP and still excludes lyric search");
    SGTestPiPState(NO, NO, NO);
}
