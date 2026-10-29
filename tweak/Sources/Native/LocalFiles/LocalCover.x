// A local file's own cover where the native player shows Spotify's placeholder (Shared/LocalFiles/
// LocalCover.m finds it). Spotify's player keeps a list of covers scrolled sideways, a cell per track in
// the queue (Native/Player/Player.x), and the cell under the list's middle is the one playing; the cover
// is the largest image view in it, 354pt across, with a 64pt glyph standing in while it has no picture.
// The cover fills an empty view; a metadata thumbnail may upgrade our provisional system artwork.
// A cover-tilt view outside the list (the cover inspected full screen) gets the same.
//
// A picture of the mod's is remembered with the track it was put in for, so a cell reused for another
// track loses it, and Spotify's own picture, once it comes, is never replaced.
#import "Core/SGCore.h"
#import "Headers/SPTPlayer.h"
#import "Shared/LocalFiles/LocalFiles.h"
#import "Shared/Player/PlayerState.h"
#import "LocalCoverFill.h"

static const CGFloat kCoverMinWidth = 200;
static __weak UIScrollView *sg_list;
static NSHashTable<UIView *> *sg_tilts;

static BOOL isCoverCell(UIView *view) {
    static Class cell, legacy;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cell = NSClassFromString(@"_TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl");
        legacy = NSClassFromString(@"_TtC28NowPlaying_ContentLayersImpl22LegacyCoverArtCellImpl");
    });
    return (cell && [view isKindOfClass:cell]) || (legacy && [view isKindOfClass:legacy]);
}

static UIImageView *largestImageIn(UIView *root) {
    __block UIImageView *largest = nil;
    __block CGFloat widest = kCoverMinWidth;
    SGForEachView(root, ^(UIView *view) {
        if (![view isKindOfClass:UIImageView.class] || view.bounds.size.width < widest) return;
        widest = view.bounds.size.width;
        largest = (UIImageView *)view;
    });
    return largest;
}

static void fillFront(UIScrollView *list) {
    CGFloat middle = list.contentOffset.x + list.bounds.size.width / 2;
    for (UIView *cell in list.subviews) {
        if (!isCoverCell(cell) || middle < CGRectGetMinX(cell.frame) || middle > CGRectGetMaxX(cell.frame)) continue;
        sg_list = list;
        SGLocalCoverFill(largestImageIn(cell));
    }
}

// The track changing, or the now playing info catching up with it a moment later, lays nothing out. The
// retries below cover the first seconds; artwork arriving after them is announced by LocalCover.m when the
// now playing info changes, which coverLoaded: answers.
@interface SGLocalCoverWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGLocalCoverWatcher
- (void)coverLoaded:(NSNotification *)note {
    if (![note.object isEqual:SGURIString(SGPlayerState().track.URI)]) return;
    UIScrollView *list = sg_list;
    if (list.window) fillFront(list);
    for (UIView *tilt in sg_tilts) if (tilt.window) [tilt setNeedsLayout];
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    for (NSNumber *delay in @[@0, @1.5]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIScrollView *list = sg_list;
            if (list.window) fillFront(list);
        });
    }
}
@end

%hook _TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView
- (void)layoutSubviews {
    %orig;
    fillFront((UIScrollView *)self);
}
%end

%hook _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView
- (void)layoutSubviews {
    %orig;
    UIView *tilt = (UIView *)self;
    if (tilt.bounds.size.width < kCoverMinWidth) return;
    // In the list the front cell is the list's to fill; elsewhere, only inside the player, since album
    // pages show their covers in the same view.
    BOOL player = NO;
    for (UIView *view = tilt.superview; view; view = view.superview) {
        if (isCoverCell(view)) return;
        player = player || SGClassNamed(view.class, @"NowPlaying");
    }
    if (player) {
        if (!sg_tilts) sg_tilts = [NSHashTable weakObjectsHashTable];
        [sg_tilts addObject:tilt];
        SGLocalCoverFill(largestImageIn(tilt));
    }
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
    static SGLocalCoverWatcher *watcher;
    watcher = [SGLocalCoverWatcher new];
    SGAddPlayerStateObserver(watcher);
    [NSNotificationCenter.defaultCenter addObserver:watcher selector:@selector(coverLoaded:)
        name:SGLocalFileFallbackCoverDidChangeNotification object:nil];
    SGRequireClasses(@[
        @"_TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView",
        @"_TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView",
        @"_TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl",
    ]);
}
