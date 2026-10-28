// Album redesign, Play counts In menu: a track's plays as a line of information on the sheet its row's ⋯ opens,
// instead of on the row.
//
// The sheet is Spotify's ContextMenu_InternalImpl.ContextMenuViewController, whose rows come from item factories
// nothing can be put between; the table's header or footer can be set, as Playlist/PlaylistMenu.x and
// Shared/Player/SpeedPitchMenu.x do. So the line goes in the header, above Spotify's rows, or in the footer where
// Spotify uses the header, and nowhere where it uses both. Once in, a slot Spotify fills with a view of its own is
// Spotify's: the line gives way for the rest of that sheet. Which sheet is the track's: the row's ⋯ says so as it
// sends its action (AlbumRows.x), and a sheet that first lays out within kMarkWindow of that takes it.
//
// The line reads as information rather than a row to tap: footnote text in the secondary label color at the
// sheet's margin, no glyph, a hairline between it and Spotify's rows, and as tall as its text at any text size.
//
// The count is asked again at each of the sheet's passes and whenever the counts change while the sheet is there
// (the log may still be being read as it comes up, or be erased while it is up); none, and there is no line.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Album.h"
#import "AlbumSpotifyCounts.h"

static NSString *const kSheetClass = @"_TtC24ContextMenu_InternalImpl25ContextMenuViewController";
// From the action of a row's ⋯ to the first pass of the sheet it opens.
static const NSTimeInterval kMarkWindow = 1.5;
// The sheet's side margin, as Playlist/PlaylistMenu.x takes it, and the room above and below the text.
static const CGFloat kSideMargin = 16, kVerticalPadding = 12;

static NSString *sg_markedAlbum, *sg_markedTitle;
static SGRAlbumCountPage *sg_markedSpotifyPage;
static CFTimeInterval sg_markedAt;
static char kTrackKey, kInfoKey;
static NSMutableSet<NSString *> *sg_logged;

void SGRAlbumPlaysMarkMenu(NSString *album, NSString *title) {
    sg_markedSpotifyPage = nil;
    BOOL marked = album.length && title.length;
    sg_markedAlbum = marked ? [album copy] : nil;
    sg_markedTitle = marked ? [title copy] : nil;
    sg_markedAt = CACurrentMediaTime();
}

void SGRAlbumPlaysMarkSpotifyMenu(NSString *trackURI, SGRAlbumCountPage *page) {
    SGRAlbumPlaysMarkMenu(page.albumURI, trackURI);
    if (sg_markedAlbum) sg_markedSpotifyPage = page;
}

// The sheets with a track whose line may still come, go or change.
static NSHashTable<UIViewController *> *liveSheets(void) {
    static NSHashTable<UIViewController *> *sheets;
    if (!sheets) sheets = [NSHashTable weakObjectsHashTable];
    return sheets;
}

static void install(UIViewController *sheet);

@interface SGRPlaysInfoRow : UIView
@property (nonatomic) BOOL inFooter;
@property (nonatomic, weak) UIViewController *sheet;
- (void)showText:(NSString *)text;
- (CGFloat)heightForWidth:(CGFloat)width;
@end

@implementation SGRPlaysInfoRow {
    UILabel *_text;
    UIView *_rule;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    _text = [UILabel new];
    _text.textColor = UIColor.secondaryLabelColor;
    _text.numberOfLines = 0;
    [self addSubview:_text];
    _rule = [UIView new];
    _rule.backgroundColor = UIColor.separatorColor;
    [self addSubview:_rule];
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitStaticText;
    return self;
}

- (void)showText:(NSString *)text {
    if ([_text.text isEqualToString:text]) return;
    _text.text = text;
    self.accessibilityLabel = text;
    [self setNeedsLayout];
}

// Measured in the text size the line has now: the font is set here rather than left to the label's own trait
// change, which lands after the line's and so after the sheet has been asked to measure it.
- (CGFloat)heightForWidth:(CGFloat)width {
    _text.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote compatibleWithTraitCollection:self.traitCollection];
    CGFloat text = [_text sizeThatFits:CGSizeMake(MAX(0, width - 2 * kSideMargin), CGFLOAT_MAX)].height;
    return ceil(text) + 2 * kVerticalPadding;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    _text.frame = CGRectMake(kSideMargin, kVerticalPadding, MAX(0, bounds.size.width - 2 * kSideMargin), MAX(0, bounds.size.height - 2 * kVerticalPadding));
    // On the side that faces Spotify's rows.
    CGFloat hairline = 1 / (self.window.screen.scale ?: UIScreen.mainScreen.scale);
    _rule.frame = CGRectMake(kSideMargin, self.inFooter ? 0 : bounds.size.height - hairline, MAX(0, bounds.size.width - kSideMargin), hairline);
}

// A new text size measures the line again.
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    UIViewController *sheet = self.sheet;
    if (sheet && ![previous.preferredContentSizeCategory isEqualToString:self.traitCollection.preferredContentSizeCategory]) install(sheet);
}

@end

// The track this sheet is for, decided at its first pass and only from a row's ⋯ just before; the mark is used up by
// the first sheet that asks, whichever it is.
static NSArray *trackFor(UIViewController *sheet) {
    id decided = objc_getAssociatedObject(sheet, &kTrackKey);
    if (decided) return decided == NSNull.null ? nil : decided;
    NSArray *track = sg_markedAlbum && CACurrentMediaTime() - sg_markedAt <= kMarkWindow
        ? @[sg_markedAlbum, sg_markedTitle, sg_markedSpotifyPage ?: (id)NSNull.null] : nil;
    sg_markedAlbum = sg_markedTitle = nil;
    sg_markedSpotifyPage = nil;
    objc_setAssociatedObject(sheet, &kTrackKey, track ?: (id)NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return track;
}

// The sheet shows no line from now on.
static void giveUp(UIViewController *sheet) {
    objc_setAssociatedObject(sheet, &kTrackKey, NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [liveSheets() removeObject:sheet];
}

static NSString *nameOf(UIView *view) {
    return view ? NSStringFromClass(view.class) : @"nothing";
}

static void setSlot(UITableView *table, BOOL footer, UIView *view) {
    // Outside the sheet's rise, or the line slides in from the table's top.
    [UIView performWithoutAnimation:^{
        if (footer) table.tableFooterView = view;
        else table.tableHeaderView = view;
        [table invalidateIntrinsicContentSize];
    }];
}

static void install(UIViewController *sheet) {
    UIView *root = sheet.viewIfLoaded;
    NSArray *track = root ? trackFor(sheet) : nil;
    if (!track) return;
    UITableView *table = SGTableIn(root, 6);
    if (!table) {
        // Asked again at the next pass: the table may come in after the sheet's first.
        SGLogOnce(&sg_logged, [@"no table under " stringByAppendingString:nameOf(root)], @"redesign album: a track's sheet has %@ so far, its plays wait");
        return;
    }
    [liveSheets() addObject:sheet];
    CGFloat width = table.bounds.size.width;
    if (width <= 0) return;
    NSString *text;
    if (track[2] != NSNull.null) {
        SGRAlbumCountPage *page = track[2];
        text = [page.albumURI isEqual:track[0]] ? SGRAlbumSpotifyPlaysText(page.counts[track[1]]) : nil;
    } else text = SGRAlbumPlaysText(SGRAlbumPlayCount(track[0], track[1]));
    SGRPlaysInfoRow *info = objc_getAssociatedObject(sheet, &kInfoKey);
    if (!info) {
        if (!text) return;
        BOOL headerFree = !table.tableHeaderView || table.tableHeaderView.bounds.size.height < 1;
        BOOL footerFree = !table.tableFooterView || table.tableFooterView.bounds.size.height < 1;
        if (!headerFree && !footerFree) {
            NSString *both = [NSString stringWithFormat:@"a header (%@) and a footer (%@)", nameOf(table.tableHeaderView), nameOf(table.tableFooterView)];
            SGLogOnce(&sg_logged, both, @"redesign album: a track's sheet has %@ of Spotify's, its plays left off");
            giveUp(sheet);
            return;
        }
        info = [[SGRPlaysInfoRow alloc] initWithFrame:CGRectZero];
        info.inFooter = !headerFree;
        info.sheet = sheet;
        objc_setAssociatedObject(sheet, &kInfoKey, info, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *slot = info.inFooter ? table.tableFooterView : table.tableHeaderView;
    // A view of Spotify's put in the slot since the line went in, or since it went: the slot is Spotify's now.
    if (slot && slot != info && slot.bounds.size.height >= 1) {
        NSString *taken = [NSString stringWithFormat:@"%@ in the %@", nameOf(slot), info.inFooter ? @"footer" : @"header"];
        SGLogOnce(&sg_logged, taken, @"redesign album: Spotify put %@ of a track's sheet, its plays give way");
        giveUp(sheet);
        return;
    }
    if (!text) {
        if (slot == info) setSlot(table, info.inFooter, nil);
        return;
    }
    [info showText:text];
    CGRect frame = CGRectMake(0, 0, width, [info heightForWidth:width]);
    if (slot == info && CGRectEqualToRect(info.frame, frame)) return;
    info.frame = frame;
    setSlot(table, info.inFooter, info);
    static BOOL logged;
    if (!logged) {
        logged = YES;
        SGLog(@"redesign album: a track's plays on its ⋯ sheet, in the %@", info.inFooter ? @"footer" : @"header");
    }
}

%hook _TtC24ContextMenu_InternalImpl25ContextMenuViewController
- (void)viewDidLayoutSubviews {
    %orig;
    install((UIViewController *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (SGRAlbumPlayCountsWhere() != SGRAlbumPlayCountsInMenu) return;
    %init;
    // Posted on the main thread (AlbumPlays.m).
    [NSNotificationCenter.defaultCenter addObserverForName:SGRAlbumPlayCountsDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        for (UIViewController *sheet in liveSheets().allObjects) install(sheet);
    }];
    SGRequireClasses(@[kSheetClass]);
}
