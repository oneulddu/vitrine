// The redesign's Player page in Mod Settings (App/Pages.m opens it in place of the native look's).
//
// It leads with a card of the player as the now playing track shows on it: the background chosen on the
// page edge to edge, and over its foot the cover, the title and the artist (gliding when too long) and how
// far the track has played. The progress is where the track was when the page appeared. With no track, the
// card shows the last one played (Shared/Player/SGLastTrack.h), its cover fetched and its Canvas looked up
// as the playing one's would be, and with none ever played, Not Playing over a gradient of the accent.
//
// The background is the player's own: a field of the same kind (Still, Colors, Fluid), for Animated
// the clip the player is playing (SGRPlayerMotionPreview) in place of the field, or, while the player has
// none, the playing track's clip looked up for the card while it is on screen, Fluid until it comes in and
// for a track with none, as in the player; the clip crosses over the field as it arrives, its poster first
// while its video decodes. And for Visualizer the hills over Fluid held still (SGRPlayerVisualiserPreview),
// moving with the song. It moves under the field's own conditions (in a window, Spotify in front, Reduce
// Motion and Low Power Mode off). Under the card a segmented control picks the background, all five of
// them: the names are one word each, each segment as wide as its name, so they fit side by side at an iPhone's
// width, and every choice stays one tap away with the card showing it at once. A note under the control says what the
// choice does; it is given the room of the longest note, so the rows under it hold still as it changes.
//
// Under the header: the rows that follow the choice (Animated's sources, its full-screen cover switch, which the open
// player follows at once, SGRPlayerStillChanged, and its Low Data Mode switch; Fluid's
// sliders and their Reset, which the card and the player follow as they move, SGRFluid.h, Grain among them only
// while Smooth draws), the Controls section, whose Header glass and Music app icons switches the open player follows
// at once (SGRPlayerLookChanged), the Mini player section (Redesigned/NowPlayingBar/NowPlayingBarSettings.m), then the
// sections either look shares.
//
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRFluid.h"
#import "Redesigned/Kit/SGRFluidGPU.h"
#import "Redesigned/Kit/SGRRefinements.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/Player/SGLastTrack.h"
#import "Player.h"
#import "PlayerLyricLine.h"

// The card's height as a share of its width, kept between the two bounds.
static const CGFloat kCardAspect = 0.5, kCardMinHeight = 168, kCardMaxHeight = 220;
static const CGFloat kCardRadius = 26;   // continuous, the radius of the page's own cards and then some
static const CGFloat kCardPadding = 16, kCoverSide = 64;

// What each background does, in SGRPlayerBackgroundKind's order.
static NSArray<NSString *> *backgroundNotes(void) {
    return @[
        SGL(@"settings.player.bg_desc.still", @"The cover, blurred and held still."),
        SGL(@"settings.player.bg_desc.colors", @"The cover's colors, drifting slowly."),
        SGL(@"settings.player.bg_desc.fluid", @"The cover itself, blurred and slowly turning. It rests while a song is paused."),
        SGL(@"settings.player.bg_desc.animated", @"The song's Canvas or the album's moving cover, else Fluid. The player's ⋯ menu switches between this, Fluid and Visualizer."),
        SGL(@"settings.player.bg_desc.visualizer", @"The song's sound in Hills, Bars, Nebula or Halo, or its synced lyrics in Lyrics, Poster or Cut, over Fluid held still. Choose a style below; it settles on pause or silence."),
        SGL(@"settings.player.bg_desc.black", @"Pure black, nothing of the cover."),
        SGL(@"settings.player.bg_desc.photo", @"A photo of your own, darkened so the words over it stay easy to read."),
    ];
}

// "Behind the player": the artwork's choices, black, or a photo, in that order.
static NSArray<NSString *> *behindNames(void) {
    return @[SGL(@"settings.player.behind.artwork", @"Artwork"), SGL(@"settings.player.behind.black", @"Black"),
             SGL(@"settings.player.behind.photo", @"Your Photo")];
}

// The segment of an artwork's choice; none is lit under black or a photo.
static NSInteger segmentOf(SGRPlayerBackgroundKind kind) {
    return SGRPlayerBackgroundFromArtwork(kind) ? kind : UISegmentedControlNoSegment;
}

@interface SGRPlayerShowcase : UIView <SGPlayerStateObserver>
- (void)reloadTrack;
- (void)reloadBackgroundAnimated:(BOOL)animated;
@end

@implementation SGRPlayerShowcase {
    SGRArtworkField *_field;
    UIView *_motion, *_visualiser, *_backdrop;
    UIImageView *_cover;
    SGMarqueeLabel *_title, *_artist;
    UIView *_progress, *_progressFill;
    CGFloat _position;
    NSString *_artworkOf;   // the last track whose cover the card asked for
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.clipsToBounds = YES;
    self.layer.cornerRadius = kCardRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.backgroundColor = SGRNeutralField();
    self.userInteractionEnabled = NO;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitImage;
    self.accessibilityLabel = SGL(@"settings.player.preview.a11y", @"Player preview");

    _field = [[SGRArtworkField alloc] initWithFrame:frame];
    _field.showsBackdrop = YES;
    [self addSubview:_field];

    _cover = [UIImageView new];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerRadius = 8;
    _cover.layer.cornerCurve = kCACornerCurveContinuous;
    _cover.tintColor = SGRTertiary();
    _cover.backgroundColor = SGRSolidGlassFill();
    _cover.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
    [self addSubview:_cover];

    // The card reads as one image; the words glide as the player's own do.
    _title = [SGMarqueeLabel new];
    _title.textColor = SGRPrimary();
    _title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _title.isAccessibilityElement = NO;
    [self addSubview:_title];
    _artist = [SGMarqueeLabel new];
    _artist.textColor = SGRSecondary();
    _artist.font = [UIFont systemFontOfSize:15];
    _artist.isAccessibilityElement = NO;
    [self addSubview:_artist];

    // The player's slider as it is drawn at rest: a track, and in it a fill up to where the song is.
    _progress = [UIView new];
    _progress.backgroundColor = [UIColor colorWithWhite:1 alpha:0.2];
    _progress.clipsToBounds = YES;
    _progressFill = [UIView new];
    _progressFill.backgroundColor = SGRPrimary();
    [_progress addSubview:_progressFill];
    [self addSubview:_progress];

    SGAddPlayerStateObserver(self);
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(artworkChanged) name:SGRNowPlayingArtworkDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateAccessibilityValue) name:SGRVisualiserStyleDidChangeNotification object:nil];
    [self reloadTrack];
    [self reloadBackgroundAnimated:NO];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    [self reloadTrack];
}

- (void)artworkChanged {
    NSString *identity = nil;
    UIImage *image = SGRNowPlayingArtwork(NULL, &identity);
    if (image) [self showArtwork:image identity:identity];
}

// The cover and the field from `image`, or from the placeholder for nil.
- (void)showArtwork:(UIImage *)image identity:(NSString *)identity {
    static UIImage *placeholder;
    static UIColor *tint;
    if (!image && (!placeholder || ![tint isEqual:SGGreen()])) {
        tint = SGGreen();
        placeholder = SGPlaceholderArtwork(tint);
    }
    _cover.image = image ?: placeholder;
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    [_field setArtwork:_cover.image identity:image ? identity : @"placeholder" animated:self.window != nil];
}

// The track, where it is and whether it plays, read again.
- (void)reloadTrack {
    SPTPlayerState *state = SGPlayerState();
    SGShownTrack *shown = SGShownTrackNow();
    _title.text = shown.title ?: SGL(@"settings.player.not_playing", @"Not Playing");
    _artist.text = shown.artist ?: @"";
    _position = shown.current && state.duration > 0 ? MIN(1, MAX(0, state.position / state.duration)) : 0;
    // The clip covers the field, and the hills move over it, which then holds still, as in the player.
    _field.motionHeld = state.isPaused || _motion != nil || _visualiser != nil || _backdrop != nil;
    if (shown.current && SGRNowPlayingArtwork(NULL, NULL)) {
        [self artworkChanged];
    } else if (!shown.current && shown.artworkURL) {
        // The last track's cover, the placeholder until it comes.
        NSString *uri = shown.uri;
        if (![_artworkOf isEqualToString:uri]) [self showArtwork:nil identity:nil];
        _artworkOf = uri;
        __weak SGRPlayerShowcase *weakSelf = self;
        SGShownTrackArtwork(shown, ^(UIImage *image) {
            SGRPlayerShowcase *showcase = weakSelf;
            SGShownTrack *now = SGShownTrackNow();
            if (image && !now.current && [now.uri isEqualToString:uri]) [showcase showArtwork:image identity:[@"last:" stringByAppendingString:uri]];
        });
    } else {
        // Nothing ever played, or the playing track's cover still coming.
        _artworkOf = nil;
        [self showArtwork:nil identity:nil];
    }
    [self setNeedsLayout];
}

// The card on screen with Animated and no clip in it: one is looked up, and shown once it is in.
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window && !_motion && SGRPlayerBackground() == SGRPlayerBackgroundAnimated) [self reloadBackgroundAnimated:NO];
}

// The background chosen, read again; a new one crosses over when animated. The clip is the one playing, or
// looked up, when this is called: a track changed while the page shows keeps the last one until the page
// appears again. A clip is looked up only while the card is in a window.
- (void)reloadBackgroundAnimated:(BOOL)animated {
    SGRPlayerBackgroundKind kind = SGRPlayerBackground();
    __weak SGRPlayerShowcase *weakSelf = self;
    void (^arrived)(void) = !self.window ? nil : ^{
        SGRPlayerShowcase *showcase = weakSelf;
        if (showcase.window && !showcase->_motion && SGRPlayerBackground() == SGRPlayerBackgroundAnimated) [showcase reloadBackgroundAnimated:YES];
    };
    // Black or the photo lies over a field made as the artwork's last choice, as in the player.
    SGRPlayerBackgroundKind look = SGRPlayerArtworkBackground();
    void (^apply)(void) = ^{
        self->_field.flows = look == SGRPlayerBackgroundColours;
        self->_field.fluid = look >= SGRPlayerBackgroundFluid;
        [self->_backdrop removeFromSuperview];
        self->_backdrop = SGRPlayerBackdropPreview();
        if (self->_backdrop) [self insertSubview:self->_backdrop aboveSubview:self->_field];
        [self->_motion removeFromSuperview];
        self->_motion = kind == SGRPlayerBackgroundAnimated ? SGRPlayerMotionPreview(arrived) : nil;
        if (self->_motion) [self insertSubview:self->_motion aboveSubview:self->_field];
        [self->_visualiser removeFromSuperview];
        self->_visualiser = kind == SGRPlayerBackgroundVisualiser ? SGRPlayerVisualiserPreview() : nil;
        if (self->_visualiser) [self insertSubview:self->_visualiser aboveSubview:self->_field];
        self->_field.motionHeld = SGPlayerState().isPaused || self->_motion != nil || self->_visualiser != nil || self->_backdrop != nil;
    };
    [self updateAccessibilityValue];
    if (animated && self.window) {
        // A crossfade, which Reduce Motion keeps: nothing moves.
        [UIView transitionWithView:self duration:SGRCrossfade options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowAnimatedContent
                        animations:apply completion:nil];
    } else {
        apply();
    }
    [self setNeedsLayout];
}

- (void)updateAccessibilityValue {
    // Describe what the showcase actually contains, even while the player's background change is pending.
    SGRPlayerBackgroundKind kind = SGRPlayerBackground();
    NSString *name = SGRPlayerBackgroundFromArtwork(kind) ? SGRPlayerBackgroundNames()[(NSUInteger)kind]
                   : behindNames()[kind == SGRPlayerBackgroundBlack ? 1 : 2];
    self.accessibilityValue = kind == SGRPlayerBackgroundVisualiser
        ? [NSString stringWithFormat:SGL(@"settings.player.bg_visualizer.format", @"Visualizer background, %@"), SGRVisualiserStyleNames()[[SGRVisualiserStyleIDs() indexOfObject:SGRVisualiserStyle()]]]
        : [name stringByAppendingString:SGL(@"settings.player.bg_suffix", @" background")];
}

// The clip runs from the card's top at its width, as in the player, and its blur comes in from the
// seam under the controls, which on a card this short is over its foot, under the words.
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGFloat w = bounds.size.width, h = bounds.size.height;
    _field.frame = bounds;
    _field.backdropHeight = h;
    _motion.frame = bounds;
    _visualiser.frame = bounds;
    _backdrop.frame = bounds;

    _cover.frame = CGRectMake(kCardPadding, h - kCardPadding - kCoverSide, kCoverSide, kCoverSide);
    CGFloat x = CGRectGetMaxX(_cover.frame) + 12, width = w - kCardPadding - x;
    CGFloat line = 4, titleHeight = ceil(_title.font.lineHeight), artistHeight = ceil(_artist.font.lineHeight);
    CGFloat bottom = CGRectGetMaxY(_cover.frame);
    _progress.frame = CGRectMake(x, bottom - line - 2, width, line);
    _progress.layer.cornerRadius = line / 2;
    _progressFill.frame = CGRectMake(0, 0, round(width * _position), line);
    CGFloat textBottom = CGRectGetMinY(_progress.frame) - 10;
    _artist.frame = CGRectMake(x, textBottom - artistHeight, width, artistHeight);
    _title.frame = CGRectMake(x, CGRectGetMinY(_artist.frame) - titleHeight, width, titleHeight);
}

@end

#pragma mark - the page

@interface SGRPlayerPage : SGModPage
@property (nonatomic, strong) SGRPlayerShowcase *showcase;
@property (nonatomic, strong) UISegmentedControl *backgrounds;
- (void)backgroundChanged;
@end

@implementation SGRPlayerPage {
    UIView *_header;
    UILabel *_note;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _header = [UIView new];
    [_header addSubview:self.showcase];
    [_header addSubview:self.backgrounds];
    _note = [UILabel new];
    _note.font = SGSubtitleFont();
    _note.textColor = SGGrey();
    _note.numberOfLines = 0;
    [_header addSubview:_note];
    [self showNote];
    self.tableView.tableHeaderView = _header;
}

- (void)showNote {
    _note.text = backgroundNotes()[(NSUInteger)SGRPlayerBackground()];
    [self.view setNeedsLayout];
}

// The header keeps the height it is given, so it is sized here and given back to the table only when that
// changes (a table header set on every pass lays the table out again forever). The note's room is that of
// the longest note at this width, so picking a background never moves the rows.
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    UITableView *table = self.tableView;
    _note.font = SGSubtitleFont();
    CGFloat width = table.bounds.size.width, inset = table.layoutMargins.left;
    CGFloat cardWidth = width - 2 * inset;
    CGFloat cardHeight = round(MIN(kCardMaxHeight, MAX(kCardMinHeight, cardWidth * kCardAspect)));
    self.showcase.frame = CGRectMake(inset, 16, cardWidth, cardHeight);
    CGFloat controlHeight = MAX(32, ceil([self.backgrounds sizeThatFits:CGSizeMake(cardWidth, CGFLOAT_MAX)].height));
    self.backgrounds.frame = CGRectMake(inset, CGRectGetMaxY(self.showcase.frame) + 12, cardWidth, controlHeight);

    CGFloat noteWidth = cardWidth - 2 * 4, room = 0;
    UILabel *measure = [UILabel new];
    measure.font = _note.font;
    measure.numberOfLines = 0;
    for (NSString *text in backgroundNotes()) {
        measure.text = text;
        room = MAX(room, ceil([measure sizeThatFits:CGSizeMake(noteWidth, CGFLOAT_MAX)].height));
    }
    CGFloat noteHeight = ceil([_note sizeThatFits:CGSizeMake(noteWidth, CGFLOAT_MAX)].height);
    CGFloat noteTop = CGRectGetMaxY(self.backgrounds.frame) + 8;
    _note.frame = CGRectMake(inset + 4, noteTop, noteWidth, noteHeight);
    CGSize size = CGSizeMake(width, noteTop + room);
    if (CGSizeEqualToSize(_header.bounds.size, size)) return;
    _header.frame = (CGRect){CGPointZero, size};
    table.tableHeaderView = _header;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // The player's ⋯ menu can switch Animated and Fluid while the page is away.
    self.backgrounds.selectedSegmentIndex = segmentOf(SGRPlayerBackground());
    [self showNote];
    [self.showcase reloadTrack];
    [self.showcase reloadBackgroundAnimated:NO];
}

- (void)backgroundPicked {
    SGRSetPlayerBackground(self.backgrounds.selectedSegmentIndex);
    SGSetInt(SGRKeyPlayerArtworkBackground, self.backgrounds.selectedSegmentIndex);
    [self backgroundChanged];
}

// The card, the segments, the note and the rows that follow the choice, after it changed here or in a row.
- (void)backgroundChanged {
    SGRPlayerBackgroundDidChange();
    self.backgrounds.selectedSegmentIndex = segmentOf(SGRPlayerBackground());
    [self.showcase reloadBackgroundAnimated:YES];
    [self showNote];
    [self refreshVisibility];
    [self.tableView reloadData];
}

@end

#pragma mark - switches the open player follows

static NSHashTable<UIView *> *sg_lookViews;

void SGRPlayerWatchLook(UIView *unitView) {
    if (!unitView) return;
    if (!sg_lookViews) sg_lookViews = [NSHashTable weakObjectsHashTable];
    [sg_lookViews addObject:unitView];
}

void SGRPlayerLookChanged(void) {
    for (UIView *view in sg_lookViews.allObjects) [view setNeedsLayout];
}

// One of Fluid's settings on a slider, written out with `unit` after the number.
static SGModRow *fluidSlider(NSString *title, SGRFluidSetting setting, NSString *unit) {
    SGRFluidLimits l = SGRFluidLimitsOf(setting);
    return SGSliderRow(title, nil, l.least, l.most, l.step, ^double { return SGRFluidValue(setting); },
                       ^(double value) { SGRSetFluidValue(setting, lround(value)); },
                       ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f%@", value, unit]; });
}

SGModRow *SGRVisualiserStyleRow(void) {
    return SGMenuRow(SGL(@"settings.player.visualizer_style.title", @"Visualizer style"), SGRVisualiserStyleNames(), ^NSString *{
        return SGRVisualiserStyleNames()[[SGRVisualiserStyleIDs() indexOfObject:SGRVisualiserStyle()]];
    }, ^(NSInteger index) {
        NSArray<NSString *> *identifiers = SGRVisualiserStyleIDs();
        if (index >= 0 && (NSUInteger)index < identifiers.count) SGRPickVisualiserStyle(identifiers[(NSUInteger)index]);
    });
}

// A Poster or Cut parameter's rows (PlayerLyricStages.m), shown only while that style is chosen. The switches keep
// their value in the parameters' dictionary, so the search remembers them by the entry they store.
static SGModRow *visualiserSwitch(NSString *title, NSString *style, NSString *param) {
    SGModRow *row = SGBlockSwitchRow(title, nil, ^BOOL { return SGRVisualiserParam(style, param) != 0; },
                                     ^(BOOL on) { SGRSetVisualiserParam(style, param, on); });
    row.searchIdentifier = [NSString stringWithFormat:@"%@.%@.%@", SGRKeyVisualiserParams, style, param];
    row.visible = ^BOOL { return [SGRVisualiserStyle() isEqualToString:style]; };
    return row;
}

static SGModRow *visualiserSlider(NSString *title, NSString *style, NSString *param) {
    SGRVisualiserParamLimits l = SGRVisualiserParamLimitsOf(style, param);
    SGModRow *row = SGSliderRow(title, nil, l.least, l.most, l.step, ^double { return SGRVisualiserParam(style, param); },
                                ^(double value) { SGRSetVisualiserParam(style, param, value); },
                                ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f%%", value * 100]; });
    row.visible = ^BOOL { return [SGRVisualiserStyle() isEqualToString:style]; };
    return row;
}

static SGModRow *visualiserColour(NSString *title, NSString *style, NSString *param) {
    SGModRow *row = SGStatActionRow(title, nil, ^NSString *{
        return [NSString stringWithFormat:@"#%06lX", lround(SGRVisualiserParam(style, param))];
    }, ^{
        SGPickColor(title, lround(SGRVisualiserParam(style, param)), ^(NSInteger rgb) { SGRSetVisualiserParam(style, param, rgb); });
    });
    row.swatch = ^UIColor *{ return SGColorRGB(lround(SGRVisualiserParam(style, param))); };
    row.visible = ^BOOL { return [SGRVisualiserStyle() isEqualToString:style]; };
    return row;
}

UIViewController *SGRVisualiserSettingsPage(void) {
    NSString *ink = SGL(@"settings.visualizer.ink.title", @"Type color");
    NSArray<SGModRow *> *poster = @[
        visualiserSwitch(SGL(@"settings.visualizer.halftone.title", @"Halftone"), SGRVisualiserPosterID, SGRVisualiserHalftone),
        visualiserColour(ink, SGRVisualiserPosterID, SGRVisualiserInk),
        visualiserSlider(SGL(@"settings.visualizer.backdrop.title", @"Print strength"), SGRVisualiserPosterID, SGRVisualiserBackdrop),
        visualiserSlider(SGL(@"settings.visualizer.ghost.title", @"Words ahead"), SGRVisualiserPosterID, SGRVisualiserGhost)];
    NSArray<SGModRow *> *cut = @[
        visualiserColour(ink, SGRVisualiserCutID, SGRVisualiserInk),
        visualiserSlider(SGL(@"settings.visualizer.shade.title", @"Background"), SGRVisualiserCutID, SGRVisualiserShade),
        visualiserSlider(SGL(@"settings.visualizer.motion.title", @"Motion"), SGRVisualiserCutID, SGRVisualiserMotion),
        visualiserSwitch(SGL(@"settings.visualizer.subtitle.title", @"Whole line"), SGRVisualiserCutID, SGRVisualiserSubtitle)];
    // Picking a style brings its rows in and takes the last one's away.
    __block __weak SGModPage *weakPage;
    SGModRow *style = SGRVisualiserStyleRow();
    void (^pick)(NSInteger) = style.chosen;
    style.chosen = ^(NSInteger index) {
        pick(index);
        [weakPage refreshVisibility];
    };
    SGModRow *shuffle = SGOptionRow(SGL(@"settings.player.visualizer_shuffle.title", @"Shuffle styles"),
                                    SGL(@"settings.player.visualizer_shuffle.subtitle", @"A different style with each song"), SGRKeyVisualiserShuffle);
    shuffle.changed = ^(BOOL on) { SGRVisualiserShuffleChanged(); };
    SGModRow *heat = SGOptionRow(SGL(@"settings.player.visualizer_heat.title", @"Ignore heat warnings"),
                                 SGL(@"settings.player.visualizer_heat.subtitle", @"Keeps the Visualizer moving while the iPhone is hot. Uses more battery."),
                                 SGRKeyVisualiserIgnoreHeat);
    heat.changed = ^(BOOL on) { SGRVisualiserIgnoreHeatChanged(); };
    SGModPage *page = [[SGModPage alloc] initWithTitle:SGL(@"settings.player.visualizers.title", @"Visualizers") intro:SGL(@"settings.player.visualizers.intro", @"Local styles for the redesigned player's Visualizer background.")
        sections:@[SGNotedSection(nil, @[style, shuffle],
            SGL(@"settings.player.visualizers.note", @"Hills: soft spectrum hills. Bars: a mirrored spectrum with the actual audio waveform. "
             @"Nebula: slow clouds in the cover's colors. Halo: a dim turning cover with a spectrum ring. Lyrics: the sung line, large, "
             @"over quieter hills. Poster: the line filled in word by word as a type poster over a print of the cover. Cut: one word "
             @"at a time over the cover, cut to the singing. The last three need synced lyrics.")),
                   SGNotedSection(SGL(@"settings.visualizer.style.choice.poster", @"Poster"), poster,
                                  SGL(@"settings.visualizer.poster.note", @"The sung line set word by word as a type poster over a print of the cover. Needs synced lyrics.")),
                   SGNotedSection(SGL(@"settings.visualizer.style.choice.cut", @"Cut"), cut,
                                  SGL(@"settings.visualizer.cut.note", @"One word at a time over the cover, cut to the singing. Needs synced lyrics.")),
                   SGSection(nil, @[heat])]
        footer:SGL(@"settings.player.visualizers.footer", @"The style changes immediately in existing player and preview visualizers. To show it, choose Visualizer "
                @"under Player > Background. This page leaves the background choice unchanged. Motion rests on pause or silence "
                @"and stops in the background, during player transitions, in Low Power Mode or when the device is hot.")];
    weakPage = page;
    return page;
}

SGModRow *SGRLyricsHideRow(void) {
    SGModRow *row = SGChoiceRow(SGL(@"settings.lyrics.hide_controls.title", @"Hide the controls"), SGL(@"settings.lyrics.hide_controls.room", @"A few seconds after the last touch, the lyrics take the room"),
                                SGRKeyLyricsAutoHide, @[SGL(@"common.off", @"Off"), SGL(@"settings.lyrics.hide_controls.all", @"Everything"), SGL(@"settings.lyrics.hide_controls.keep_title", @"Keep the title")], SGRLyricsHideMode());
    row.choiceNotes = @[SGL(@"settings.lyrics.hide_controls.off_note", @"The controls stay"), SGL(@"settings.lyrics.hide_controls.all_note", @"The lyrics take the whole player"), SGL(@"settings.lyrics.hide_controls.title_note", @"The cover, the title and the top row stay; in landscape, the title")];
    return row;
}

UIViewController *SGRPlayerSettingsPage(NSArray *more) {
    SGRPlayerShowcase *showcase = [[SGRPlayerShowcase alloc] initWithFrame:CGRectMake(0, 0, 320, kCardMinHeight)];
    UISegmentedControl *backgrounds = [[UISegmentedControl alloc] initWithItems:SGRPlayerBackgroundNames()];
    backgrounds.selectedSegmentIndex = segmentOf(SGRPlayerBackground());
    backgrounds.accessibilityLabel = SGL(@"settings.player.background.a11y", @"Background");
    backgrounds.apportionsSegmentWidthsByContent = YES;

    SGModRow *lowData = SGOptionRow(SGL(@"settings.player.motion_low_data.title", @"Download in Low Data Mode"), SGL(@"settings.player.motion_low_data.subtitle", @"Up to about 7 MB a song. Applies to animated artwork throughout Vitrine."), SGKeyMotionLowData);
    lowData.visible = ^BOOL { return SGRPlayerBackground() == SGRPlayerBackgroundAnimated; };
    SGModRow *sources = SGMotionSourcesRow();
    sources.visible = lowData.visible;
    SGModRow *still = SGWithNew(SGOptionRow(SGL(@"settings.player.animated_still.title", @"Full-screen cover without a clip"),
                                            SGL(@"settings.player.animated_still.subtitle", @"A song with no clip shows its cover art. With this on, the "
                                                @"cover fills the screen the way a clip does. Low Power Mode and Reduce Motion keep the cover art."),
                                            SGRKeyPlayerAnimatedStill), @"playerAnimatedStill");
    still.visible = lowData.visible;
    still.changed = ^(BOOL on) { SGRPlayerStillChanged(); };
    SGModRow *fallback = SGWithNew(SGOptionRow(SGL(@"settings.player.animated_visualizer.title", @"Visualizer when there's no clip"),
                                               SGL(@"settings.player.animated_visualizer.subtitle", @"A song with no clip shows the Visualizer. Low Power Mode and "
                                                   @"Reduce Motion keep the cover art."),
                                               SGRKeyPlayerAnimatedVisualiser), @"playerAnimatedVisualizer");
    fallback.visible = lowData.visible;
    fallback.changed = ^(BOOL on) { SGRPlayerAnimatedVisualiserChanged(); };
    SGModRow *visualiserStyle = SGRVisualiserStyleRow();
    visualiserStyle.visible = ^BOOL { return SGRPlayerBackground() == SGRPlayerBackgroundVisualiser; };

    // Black or a photo in place of the artwork; the photo is asked for the first time it is chosen.
    __block __weak SGRPlayerPage *weakPlayerPage;
    SGModRow *behind = SGMenuRow(SGL(@"settings.player.behind.title", @"Behind the Player"), behindNames(), ^NSString *{
        SGRPlayerBackgroundKind kind = SGRPlayerBackground();
        return behindNames()[kind == SGRPlayerBackgroundBlack ? 1 : kind == SGRPlayerBackgroundPhoto ? 2 : 0];
    }, ^(NSInteger index) {
        SGRPlayerPage *page = weakPlayerPage;
        if (index == 2) {
            // Reserve this choice while the saved photo is prepared or the picker imports one, without
            // replacing the current look. Every later page/menu choice supersedes its automatic switch.
            NSUInteger choice = SGRSetPlayerBackground(SGRPlayerBackground());
            SGRPlayerLoadPhoto(^(BOOL available) {
                if (choice != SGRPlayerBackgroundGeneration()) return;
                void (^usePhoto)(BOOL) = ^(BOOL stored) {
                    if (!stored || choice != SGRPlayerBackgroundGeneration()) return;
                    SGRSetPlayerBackground(SGRPlayerBackgroundPhoto);
                    [page backgroundChanged];
                };
                if (available) usePhoto(YES);
                else SGRPlayerPickPhoto(page, usePhoto);
            });
            return;
        }
        SGRSetPlayerBackground(index == 1 ? SGRPlayerBackgroundBlack : SGRPlayerArtworkBackground());
        [page backgroundChanged];
    });
    SGModRow *choosePhoto = SGActionRow(SGL(@"settings.player.photo.choose", @"Choose Photo"), nil, ^{
        SGRPlayerPage *page = weakPlayerPage;
        SGRPlayerPickPhoto(page, ^(BOOL stored) { if (stored) [page backgroundChanged]; });
    });
    choosePhoto.visible = ^BOOL { return SGRPlayerBackground() == SGRPlayerBackgroundPhoto; };

    __block __weak UITableViewController *weakPage;
    SGModRow *reset = SGActionRow(SGL(@"common.reset", @"Reset"), nil, ^{
        SGRResetFluidSettings();
        [weakPage.tableView reloadData];   // the sliders at once, rather than at the page's next tick
    });
    reset.color = SGRed();
    // Light or Smooth, the way Fluid is drawn (SGRFluid.h); the card and the player change at once.
    SGModRow *renderer = SGMenuRow(SGL(@"settings.player.fluid.renderer.title", @"Style"), SGRFluidRendererNames(), ^NSString *{
        return SGRFluidRendererNames()[SGRFluidRendererChosen()];
    }, ^(NSInteger index) {
        SGRSetFluidRenderer(index == SGRFluidRendererSmooth ? SGRFluidRendererSmooth : SGRFluidRendererLight);
        [weakPlayerPage refreshVisibility];   // Grain comes and goes with Smooth
    });
    // Grain is Smooth's alone (SGRFluid.h), so it shows only while Smooth draws.
    SGModRow *grain = fluidSlider(SGL(@"settings.player.fluid.grain", @"Grain"), SGRFluidGrain, @"%");
    NSArray<SGModRow *> *fluid = @[
        renderer, fluidSlider(SGL(@"settings.player.fluid.speed", @"Speed"), SGRFluidSpeed, @"%"), fluidSlider(SGL(@"settings.player.fluid.warp", @"Warp"), SGRFluidWarp, @"%"), fluidSlider(SGL(@"settings.player.fluid.blur", @"Blur"), SGRFluidBlur, @""),
        fluidSlider(SGL(@"settings.player.fluid.saturation", @"Saturation"), SGRFluidSaturation, @"%"), fluidSlider(SGL(@"settings.player.fluid.brightness", @"Brightness"), SGRFluidBrightness, @"%"), grain, reset,
    ];
    for (SGModRow *row in fluid) row.visible = ^BOOL { return SGRPlayerBackground() == SGRPlayerBackgroundFluid; };
    renderer.visible = ^BOOL { return SGRPlayerBackground() == SGRPlayerBackgroundFluid && SGRFluidGPUAvailable(); };
    grain.visible = ^BOOL {
        return SGRPlayerBackground() == SGRPlayerBackgroundFluid && SGRFluidGPUAvailable() && SGRFluidRendererChosen() == SGRFluidRendererSmooth;
    };
    // The header's glass and the footer's glyphs, followed by the open player at once.
    SGModRow *headerGlass = SGWithNew(SGSwitchRow(SGL(@"settings.player.header_glass.title", @"Header glass"),
                                                  SGL(@"settings.player.header_glass.subtitle", @"Glass circles behind the close and ⋯ buttons at the top of the player."),
                                                  SGRKeyPlayerHeaderGlass), @"playerHeaderGlass");
    SGModRow *musicIcons = SGWithNew(SGSwitchRow(SGL(@"settings.player.music_icons.title", @"Music app icons"),
                                                 SGL(@"settings.player.music_icons.subtitle", @"The Music app's AirPlay and queue icons in place of Spotify's under the controls."),
                                                 SGRKeyPlayerMusicIcons), @"playerMusicIcons");
    headerGlass.changed = musicIcons.changed = ^(BOOL on) { SGRPlayerLookChanged(); };

    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObjects:
        SGSection(nil, @[behind, choosePhoto]),
        SGSection(nil, @[sources, still, fallback, lowData]),
        SGSection(nil, @[visualiserStyle]),
        SGNotedSection(nil, fluid, SGL(@"settings.player.fluid.footer", @"Smooth lets the cover flow and carries the next song's cover in through it, "
                                   @"using a little more battery. Brightness above 100% can make white text harder to read. A paused song holds the "
                                   @"background still. Animated and Visualizer use these where they show Fluid.")),
        SGNotedSection(SGL(@"settings.player.controls.header", @"Controls"), @[headerGlass, SGSwitchRow(SGL(@"settings.player.volume.title", @"Volume"), nil, SGRKeyPlayerVolume),
                                      SGOptionRow(SGL(@"settings.player.follows_cover.title", @"Follow the cover"), nil, SGRKeyPlayerFollowsCover),
                                      SGWithNew(SGSwitchRow(SGL(@"settings.player.lyric_line.title", @"Lyrics Line"),
                                                  SGL(@"settings.player.lyric_line.subtitle", @"The line being sung, under the cover. Tap it to open the lyrics."),
                                                  SGRKeyPlayerLyricLine), @"playerLyricLine"),
                                      SGWithNew(SGSwitchRow(SGL(@"settings.player.rolling_digits.title", @"Rolling time digits"),
                                                  SGL(@"settings.player.rolling_digits.subtitle", @"The digits that change under the progress bar roll into place."),
                                                  SGRKeyPlayerRollingDigits), @"playerRollingDigits"),
                                      SGWithNew(SGOptionRow(SGL(@"settings.player.star_add.title", @"Star add button"),
                                                  SGL(@"settings.player.star_add.subtitle", @"The add button as a star, filled in the accent once the song is saved. In the player it takes the place of Plain checkmark."),
                                                  SGRKeyPlayerStarAdd), @"playerStarAdd"), musicIcons],
                       SGL(@"settings.player.controls.footer", @"Volume puts a slider under the controls for this iPhone, or the speaker's while Spotify plays on another device. "
                       @"Follow the cover paints the like, shuffle and repeat in the color of the song playing.")),
        SGNotedSection(SGL(@"settings.player.mini_player.header", @"Mini player"), SGRNowPlayingBarRows(),
                       SGL(@"settings.player.mini_player.footer", @"Apple Music style moves the now playing bar in between two tabs as you scroll down.")), nil];
    [sections addObjectsFromArray:more];
    // Fluid, Animated and Visualizer share the field (PlayerMotion.x reads the choice on every track, PlayerVisualiser.m
    // on the field's layout); Still and Colors are a field of another kind, made once a launch (PlayerField.x).
    NSString *footer = SGL(@"settings.player.footer", @"Fluid, Animated and Visualizer change with the next song. Still, Colors and Hide on the player apply after you restart Spotify.");
    SGRPlayerPage *page = [[SGRPlayerPage alloc] initWithTitle:SGL(@"settings.player.title", @"Player") intro:nil sections:sections footer:footer];
    weakPage = page;
    weakPlayerPage = page;
    page.showcase = showcase;
    page.backgrounds = backgrounds;
    [backgrounds addTarget:page action:@selector(backgroundPicked) forControlEvents:UIControlEventValueChanged];
    return page;
}
