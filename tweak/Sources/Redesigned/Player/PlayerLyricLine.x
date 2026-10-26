// Player redesign: the line of the lyrics being sung, one line in the gap under the cover and over the title,
// while the lyrics are not open in the player and the track has synced lines. It is the one line a place with
// room for one shows (SGKaraokeLeadLine, as the lock screen's), at the player's position less the Lyrics page's
// Delay, the way the lyrics view reads it (SGRKaraokeView's positionMs). A tap on it opens the lyrics, as the
// footer's lyrics glyph does (SGRPlayerToggleLyrics).
//
// It is a view of the mod's in SPTNowPlayingView (NowPlayingViewController's view), placed on every layout pass
// of the player, of its cover (CoverArtTiltView, which PlayerArtwork.x sizes) and of the chips' unit, centered across the cover's width in the
// room between the cover's own frame (not its paused shrink) and Spotify's bottom stack, which starts with the
// title row. A chip over the title (Switch to video) ends that room where it starts. With less room than the
// line and a gap either side, a player wider than it is tall, or Spotify's own lyric preview under the cover,
// it is not shown.
//
// It reads the line on a timer of a tenth of a second while it is in a window and Spotify is in front, not a
// display link (a CADisplayLink capped at 60 Hz drags the player's 120 Hz transitions down), and changes only
// when the line does: the new line crosses over the old one.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Player.h"
#import "PlayerLyricLine.h"

static const NSTimeInterval kTick = 0.1;
static const CGFloat kTapHeight = 44;

static char kLineKey, kStackKey;
static __weak UIView *sg_host;              // SPTNowPlayingView
static __weak UIViewController *sg_floating; // the chips over the title (FloatingElementsUnit)

BOOL SGRPlayerLyricLineOn(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ on = SGEnabled(SGRKeyPlayerLyricLine); });
    return on;
}

@interface SGRLyricLineView : UIView
@property (nonatomic) BOOL fits;   // set by the layout: there is room for it
- (void)tick;
@end

@implementation SGRLyricLineView {
    UILabel *_label;
    NSTimer *_timer;
    NSArray<SGKaraokeLine *> *_source, *_ordered;
    BOOL _timed;
    NSInteger _index;
    NSString *_text;   // the line being sung, nil for none
    BOOL _shown;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _index = NSNotFound;
    self.alpha = 0;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton | UIAccessibilityTraitUpdatesFrequently;
    self.accessibilityHint = SGL(@"settings.player.lyric_line.hint", @"Opens the lyrics.");
    _label = [[UILabel alloc] initWithFrame:self.bounds];
    _label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _label.textAlignment = NSTextAlignmentCenter;
    _label.numberOfLines = 1;
    _label.lineBreakMode = NSLineBreakByTruncatingTail;
    _label.textColor = SGRSecondary();
    _label.font = [SGRLyricLineView font];
    [self addSubview:_label];
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(clock) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(clock) name:UIApplicationDidEnterBackgroundNotification object:nil];
    return self;
}

+ (UIFont *)font {
    return SGCategoryCappedFont(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryExtraExtraExtraLarge);
}

- (CGFloat)lineHeight {
    return ceil(_label.font.lineHeight);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    _label.font = [SGRLyricLineView font];
    _label.textColor = SGRSecondary();
    [self.superview setNeedsLayout];
}

// Touches only over the words, a tap's height tall, so a swipe across the rest of the gap still reaches the covers.
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    CGFloat width = MIN(self.bounds.size.width, [_label sizeThatFits:self.bounds.size].width + 2 * SGRSideMargin);
    CGRect words = CGRectMake(CGRectGetMidX(self.bounds) - width / 2, 0, width, self.bounds.size.height);
    return CGRectContainsPoint(words, point);
}

- (void)tapped {
    if (!_shown || SGRPlayerLyricsOpen()) return;
    SGLog(@"redesign player: the line under the cover opens the lyrics");
    SGRPlayerToggleLyrics();
}

#pragma mark - the clock

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self clock];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_timer invalidate];
}

// Runs while the line is in a window and Spotify is in front; stopped otherwise.
- (void)clock {
    BOOL run = self.window && UIApplication.sharedApplication.applicationState != UIApplicationStateBackground;
    if (run == (_timer != nil)) return;
    if (!run) {
        [_timer invalidate];
        _timer = nil;
        return;
    }
    __weak SGRLyricLineView *weakSelf = self;
    _timer = [NSTimer timerWithTimeInterval:kTick repeats:YES block:^(NSTimer *timer) { [weakSelf tick]; }];
    _timer.tolerance = kTick / 2;
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    [self tick];
}

// The playing track's synced lines in time order, and the one being sung; NSNotFound when there is none to show.
- (NSInteger)currentIndex {
    NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesForTrack(SGKaraokePlayingTrack());
    if (lines != _source) {
        _source = lines;
        _ordered = lines ? SGKaraokeInTimeOrder(lines) : nil;
        _timed = lines && SGKaraokeLinesTiming(lines) != SGKaraokeTimingNone;
    }
    if (!_timed) return NSNotFound;
    NSInteger ms = SGKaraokePositionMs();
    if (ms < 0) return NSNotFound;
    NSInteger index = SGKaraokeLeadLine(_ordered, ms - SGKaraokeDelayMs());
    return index < 0 ? NSNotFound : index;
}

- (void)tick {
    NSArray<SGKaraokeLine *> *before = _source;
    NSInteger index = [self currentIndex];
    if (index != _index || _source != before) {
        _index = index;
        NSString *text = index == NSNotFound ? nil
            : [SGKaraokeLineText(_ordered[(NSUInteger)index]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        _text = text.length ? text : nil;
        self.accessibilityLabel = _text;
        [self showText:_text];
    }
    UIView *covers = SGRPlayerCoverList();
    BOOL shown = _fits && _text && !SGRPlayerLyricsOpen() && (!covers || covers.alpha > 0.01);
    if (shown == _shown) return;
    _shown = shown;
    self.userInteractionEnabled = shown;
    self.accessibilityElementsHidden = !shown;
    SGRAnimate(shown ? SGRMotionFade : SGRMotionRespond, ^{ self.alpha = shown ? 1 : 0; }, nil);
}

// A new line crosses over the one before; one coming while the line is out of sight is set at once. With no line
// the last one stays in the label for the fade out.
- (void)showText:(NSString *)text {
    if (!text || [text isEqualToString:_label.text]) return;
    UILabel *label = _label;
    if (!_shown) {
        label.text = text;
        return;
    }
    [UIView transitionWithView:label duration:SGRCrossfade
                       options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                    animations:^{ label.text = text; } completion:nil];
}

@end

#pragma mark - the room under the cover

// Whether `view` shows: neither it nor any view above it up to `root` hidden or clear.
static BOOL showsIn(UIView *view, UIView *root) {
    for (UIView *v = view; v && v != root.superview; v = v.superview) {
        if (v.hidden || v.alpha < 0.01) return NO;
    }
    return YES;
}

// The chips the floating unit shows (its buttons, labels and images with a size), as one frame in `host`;
// CGRectNull when it shows none. The unit's own alpha is left out: it is 0 while the lyrics are open.
static CGRect chipsIn(UIView *host) {
    UIView *floating = sg_floating.viewIfLoaded;
    if (!floating.window || floating.window != host.window || floating.hidden) return CGRectNull;
    __block CGRect chips = CGRectNull;
    SGForEachView(floating, ^(UIView *view) {
        if (view == floating || view.bounds.size.width < 1 || view.bounds.size.height < 1) return;
        if (![view isKindOfClass:UIControl.class] && ![view isKindOfClass:UILabel.class] && ![view isKindOfClass:UIImageView.class]) return;
        for (UIView *v = view; v && v != floating; v = v.superview) if (v.hidden || v.alpha < 0.01) return;
        chips = CGRectUnion(chips, [host convertRect:view.bounds fromView:view]);
    });
    return chips;
}

// Spotify's own lyric preview under the cover (Lyrics_NPVContainerKit.LyricsContainerView, beside the tilt
// view), shown when Spotify's lyrics setting has it.
static BOOL previewShowing(UIView *tilt, UIView *host) {
    static Class preview;
    if (!preview) preview = NSClassFromString(@"_TtC22Lyrics_NPVContainerKit19LyricsContainerView");
    if (!preview) return NO;
    for (UIView *sub in tilt.superview.subviews) {
        if ([sub isKindOfClass:preview] && sub.bounds.size.height > 1 && showsIn(sub, host)) return YES;
    }
    return NO;
}

static void placeLine(void) {
    UIView *host = sg_host;
    if (!host || !SGRPlayerLyricLineOn()) return;
    SGRLyricLineView *line = objc_getAssociatedObject(host, &kLineKey);
    if (!line) {
        line = [[SGRLyricLineView alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(host, &kLineKey, line, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGLog(@"redesign player: the line under the cover goes into %@", NSStringFromClass(host.class));
    }
    if (line.superview != host) [host addSubview:line];

    UIView *tilt = SGRPlayerShowingCover().superview;
    UIView *stack = SGRFindByIdentifier(host, @"npv.bottomStackView", &kStackKey);
    BOOL fits = NO;
    if (tilt && stack && [tilt isDescendantOfView:host] && host.bounds.size.height > host.bounds.size.width
        && !previewShowing(tilt, host)) {
        CGRect cover = [host convertRect:tilt.bounds fromView:tilt];
        CGFloat top = CGRectGetMaxY(cover), bottom = CGRectGetMinY([host convertRect:stack.bounds fromView:stack]);
        CGRect chips = chipsIn(host);
        if (!CGRectIsNull(chips) && CGRectGetMaxY(chips) > top && CGRectGetMinY(chips) < bottom) bottom = MAX(top, CGRectGetMinY(chips));
        CGFloat room = bottom - top;
        fits = room >= line.lineHeight + 2 * SGRGrid;
        if (fits) {
            CGFloat height = MIN(kTapHeight, room);
            CGRect frame = CGRectIntegral(CGRectMake(CGRectGetMinX(cover), top + (room - height) / 2, cover.size.width, height));
            if (!CGRectEqualToRect(line.frame, frame)) line.frame = frame;
        }
    }
    if (fits != line.fits) {
        line.fits = fits;
        static NSUInteger logged;
        if (logged++ < 4) SGLog(@"redesign player: the line under the cover %@ (%.0fx%.0f at %.0f)", fits ? @"has room" : @"has no room",
                                line.frame.size.width, line.frame.size.height, line.frame.origin.y);
        [line tick];
    }
}

// The cover's own layout (PlayerArtwork.x sizes it there): the line follows where the cover now is. Only the
// player's covers, not the now playing bar's.
%hook _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView
- (void)layoutSubviews {
    %orig;
    UIView *host = sg_host;
    if (host && [(UIView *)self isDescendantOfView:host]) placeLine();
}
%end

%hook _TtC19NowPlaying_ViewImpl24NowPlayingViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *host = ((UIViewController *)self).viewIfLoaded;
    if (!host.window) return;
    sg_host = host;
    placeLine();
}
%end

%hook _TtC20NowPlaying_ModesImpl20FloatingElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    sg_floating = (UIViewController *)self;
    placeLine();
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGRPlayerLyricLineOn()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView",
        @"_TtC19NowPlaying_ViewImpl24NowPlayingViewController",
        @"_TtC20NowPlaying_ModesImpl20FloatingElementsUnit",
    ]);
}
