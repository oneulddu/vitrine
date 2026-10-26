// Player redesign: Playing Next, the Music app's list of what plays after the song, as a dark sheet (medium and
// large, with the system's grabber) opened from the player's ⋯ menu (PlayerMenu.m).
//
// The rows are the player state's tracks to come (SPTPlayerState.future, Headers/SPTPlayer.h), read through
// SGPlayerUpcomingTracks, as the Live Activity reads them: an SPTPlayerTrack with a title and a URI,
// the rest left out, at most kMaxRows, title over artist. Nothing is fetched: it is the state the player already
// reported. The list follows every report while the sheet is open (SGPlayerStateObserver's playerStateDidReport:,
// which carries a queue changed by hand too), reloaded only when the tracks to come changed. A tap skips ahead to
// that track (-[SPTPlayer skipToNextTrackWithOptions:track:], as the Live Activity's up next does) and closes the
// sheet.
//
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Lyrics/Lyrics.h"
#import "PlayerQueue.h"

static const NSUInteger kMaxRows = 50;

// What a row shows, so a report that changed nothing in the list leaves it alone.
static NSArray<NSString *> *signatureOf(NSArray<SPTPlayerTrack *> *tracks) {
    NSMutableArray<NSString *> *signature = [NSMutableArray arrayWithCapacity:tracks.count];
    for (SPTPlayerTrack *track in tracks) {
        [signature addObject:[NSString stringWithFormat:@"%@\t%@\t%@", SGURIString(track.URI), track.trackTitle, track.artistName ?: @""]];
    }
    return signature;
}

@interface SGRPlayerQueueController : UITableViewController <SGPlayerStateObserver>
@end

@implementation SGRPlayerQueueController {
    NSArray<SPTPlayerTrack *> *_tracks;
    NSArray<NSString *> *_signature;
    UILabel *_empty;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = SGL(@"settings.player.queue.title", @"Playing Next");
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                                         target:self action:@selector(close)];
    // From iOS 26 a sheet short of full height is Liquid Glass the system draws; a fill here would cover it.
    if (@available(iOS 26.0, *)) self.tableView.backgroundColor = UIColor.clearColor;
    _empty = [UILabel new];
    _empty.text = SGL(@"settings.player.queue.empty", @"Nothing is playing next.");
    _empty.font = SGRFont(UIFontTextStyleBody, UIFontWeightRegular, UIContentSizeCategoryAccessibilityMedium);
    _empty.textColor = SGRSecondary();
    _empty.textAlignment = NSTextAlignmentCenter;
    _empty.numberOfLines = 0;
    [self takeState:SGPlayerState()];
    SGAddPlayerStateObserver(self);
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    _empty.font = SGRFont(UIFontTextStyleBody, UIFontWeightRegular, UIContentSizeCategoryAccessibilityMedium);
}

#pragma mark - the player

- (void)takeState:(SPTPlayerState *)state {
    NSArray<SPTPlayerTrack *> *tracks = SGPlayerUpcomingTracks(state, kMaxRows);
    NSArray<NSString *> *signature = signatureOf(tracks);
    if (_signature && [signature isEqualToArray:_signature]) return;
    _tracks = tracks;
    _signature = signature;
    self.tableView.backgroundView = tracks.count ? nil : _empty;
    [self.tableView reloadData];
}

- (void)playerStateDidReport:(SPTPlayerState *)state {
    if (self.isViewLoaded) [self takeState:state];
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    if (self.isViewLoaded) [self takeState:state];
}

#pragma mark - the list

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_tracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"track"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"track"];
    cell.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    SPTPlayerTrack *track = _tracks[(NSUInteger)path.row];
    NSString *title = track.trackTitle, *artist = track.artistName.length ? track.artistName : nil;
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = title;
    content.secondaryText = artist;
    content.textProperties.color = SGRPrimary();
    content.textProperties.numberOfLines = 1;
    content.secondaryTextProperties.color = SGRSecondary();
    content.secondaryTextProperties.numberOfLines = 1;
    cell.contentConfiguration = content;
    cell.isAccessibilityElement = YES;
    cell.accessibilityLabel = artist ? [NSString stringWithFormat:@"%@, %@", title, artist] : title;
    cell.accessibilityTraits = UIAccessibilityTraitButton;
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.row >= (NSInteger)_tracks.count) return;
    SPTPlayerTrack *track = _tracks[(NSUInteger)path.row];
    id<SPTPlayer> player = SGKaraokePlayer();
    if (![player respondsToSelector:@selector(skipToNextTrackWithOptions:track:)]) {
        SGLog(@"redesign player: Playing Next cannot play %@ (player %@)", SGURIString(track.URI), player ? NSStringFromClass([player class]) : @"nil");
        return;
    }
    id result = [player skipToNextTrackWithOptions:nil track:track];
    SGLog(@"redesign player: Playing Next plays row %ld, %@ -> %@", (long)path.row, SGURIString(track.URI), result);
    [self close];
}

@end

#pragma mark - opening it

// The controller on top in `from`'s window, through whatever is presented over it; the key window's without one.
static UIViewController *topIn(UIView *from) {
    UIViewController *top = from.window.rootViewController;
    if (!top) return SGTopController();
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
    return top;
}

void SGRPlayerShowQueue(UIView *from) {
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:[SGRPlayerQueueController new]];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    SGPresentDark(navigation);
    UISheetPresentationController *sheet = navigation.sheetPresentationController;
    sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
    sheet.prefersGrabberVisible = YES;
    sheet.prefersEdgeAttachedInCompactHeight = YES;
    sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
    // Picked from the system menu, which is still going away: the sheet waits for it, as the sound panel does.
    __weak UIView *weakFrom = from;
    __block int tries = 0;
    __block void (^present)(void);
    present = ^{
        UIViewController *top = topIn(weakFrom);
        if ((top.isBeingDismissed || top.isBeingPresented || top.transitionCoordinator) && ++tries < 20) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), present);
            return;
        }
        present = nil;
        if (!top) return;
        if ([top isKindOfClass:UINavigationController.class]
            && [((UINavigationController *)top).viewControllers.firstObject isKindOfClass:SGRPlayerQueueController.class]) return;
        [top presentViewController:navigation animated:YES completion:nil];
    };
    dispatch_async(dispatch_get_main_queue(), present);
}
