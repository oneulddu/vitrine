// Artist redesign: the Music list without the artist's videos (and, each on its own switch, without the Artist pick,
// the Release Countdown and About), and nothing of it painted over the field.
//
// Tree (trees/clean/artist/05.txt, the Music list top to bottom): Popular, Artist pick, Popular releases and
// its Show all, Featuring, Release Countdown, Music videos, Watch more from…, About, Artist playlists, Fans
// also like, Appears on. Every section is three Element_List cells in a row -- a 16pt spacer, a heading
// (Components.UI.SectionHeadingHome) and what the section holds -- and every kind of content carries an
// identifier of its own, in any language: Components.UI.RetrievalRowElementUI (tracks), PinnedItemUI (the
// pick), HomeCard (a carousel), UpcomingReleaseRow, CreatorBiographyCard (About),
// Components.UI.MusicVideoShelfHeader and WatchFeedCarouselEntryPointElement (videos).
//
// So the rule is by kind, never by the heading's words, which are the app's language: a hidden section's content
// reports no height, and so do the heading and the spacer in the two cells before it. They were sized before it, so
// the list is asked to lay out again once they are known. Every carousel is the same kind whatever it holds,
// so the carousels all stay; merch has a tab of its own, which ArtistField.x takes away. With a section's switch
// off (Artist.h) its content is any other cell and stays. The pick's, the countdown's and About's identifiers are
// strings of the 9.1.78 and 9.1.90 binaries (About's as its two labels', so it matches by prefix).
//
// A dropped cell is 0 tall but what it holds keeps the height it measured at, hidden and cut off by the
// cell: content squeezed to 0 breaks Spotify's required constraints on every pass (Album/AlbumSections.x).
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Artist.h"

static char kSettledKey, kKindsKey, kDroppedKey, kInvalidateKey;

// The "You liked" row's heart sits on a 24pt black disc at the avatar's corner, a ring on any field but black
// (device 2026-10-08). The disc goes; a soft shadow keeps the heart readable on the photo.
static void clearLikedBadge(UIView *cell) {
    SGForEachView(cell, ^(UIView *row) {
        if (![row.accessibilityIdentifier isEqualToString:@"Components.UI.LikedSongs.Row"]) return;
        SGForEachView(row, ^(UIView *disc) {
            CGSize size = disc.bounds.size;
            if (size.width > 30 || size.width != size.height || !SGIsBaseSurface(disc.layer.backgroundColor)) return;
            disc.backgroundColor = UIColor.clearColor;
            disc.clipsToBounds = NO;
            disc.layer.shadowColor = UIColor.blackColor.CGColor;
            disc.layer.shadowOpacity = 0.5;
            disc.layer.shadowRadius = 2;
            disc.layer.shadowOffset = CGSizeZero;
        });
    });
}
typedef NS_ENUM(NSInteger, SGRArtistCell) {
    SGRArtistCellOther,
    SGRArtistCellSpacer,
    SGRArtistCellHeading,
    // The sections with a switch, from here on: dropped with their heading and spacer while it is on.
    SGRArtistCellVideos,
    SGRArtistCellPick,
    SGRArtistCellCountdown,
    SGRArtistCellAbout,
};
static BOOL hidden[SGRArtistCellAbout + 1];   // by kind, read at launch
static __unsafe_unretained NSString *const dropped[] = {nil, nil, nil, @"the videos", @"the Artist pick", @"the Release Countdown", @"About"};

// Spotify already owns the listeners in About (CreatorBiographyCardLayout and
// SPTArtistAboutListenersView). We only decide whether the header may omit its copy.
// Element_List's contentSnapshot is a Swift value, not an Objective-C model API.
// The list uses UIKit's diffable data source (also read by HomeFeed.swift). Its
// cell-provider callback is the configuration boundary, including reconfiguration
// that never calls prepareForReuse. A receipt binds that configuration's artist
// and item identifier to its source; layout may confirm a receipt, never invent one.
static BOOL listenersInAbout;
static char kListenersPageKey, kListenersSourceKey, kListenersConfigurationKey, kListenersUpdatingKey, kListenersConfiguringKey;

@interface SGRArtistItemConfiguration : NSObject
@property (nonatomic, weak) UICollectionViewDiffableDataSource *source;
@property (nonatomic, copy) id itemIdentifier;
@property (nonatomic, copy) NSString *identity;
@end
@implementation SGRArtistItemConfiguration @end

@interface SGRArtistAboutEvidence : NSObject
@property (nonatomic, weak) UIView *header;
@property (nonatomic, weak) UIView *metadata;
@property (nonatomic, weak) UIView *identityView;
@property (nonatomic, copy) NSString *identity;
@property (nonatomic, weak) UICollectionView *list;
@property (nonatomic, strong) SGRArtistItemConfiguration *configuration;
@property (nonatomic, copy) NSIndexPath *aboutPath;
- (void)forgetAbout;
@end

@implementation SGRArtistAboutEvidence
- (void)forgetAbout {
    if (!self.aboutPath) return;
    self.aboutPath = nil;
    self.list = nil;
    self.configuration = nil;
    [self.header setNeedsLayout];
}
@end

static BOOL currentConfiguration(SGRArtistItemConfiguration *configuration, UICollectionView *list, NSIndexPath *path) {
    if (!configuration || !path || configuration.source != list.dataSource ||
        path.section >= list.numberOfSections || path.item >= [list numberOfItemsInSection:path.section]) return NO;
    return [configuration.itemIdentifier isEqual:[configuration.source itemIdentifierForIndexPath:path]];
}

// ArtistHeader.x calls this with Spotify's own identity button and metadata.
BOOL SGRArtistListenersInAbout(UIView *header, UIView *metadata, UIView *more) {
    if (!listenersInAbout) return NO;
    UIView *page = SGRArtistPageOf(header);
    if (!page) return NO;
    SGRArtistAboutEvidence *state = objc_getAssociatedObject(page, &kListenersPageKey);
    if (!state) {
        state = [SGRArtistAboutEvidence new];
        objc_setAssociatedObject(page, &kListenersPageKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSString *identity = more.accessibilityIdentifier;
    if (![identity hasPrefix:@"Components.UI.ContextMenuButton-"]) identity = nil;
    if (![state.identity isEqualToString:identity]) {
        // Configuration/layout may precede this header pass. Keep a receipt
        // already confirmed for the incoming identity, never the old artist's.
        if (![state.configuration.identity isEqualToString:identity]) [state forgetAbout];
        state.identity = identity;
    }
    state.header = header;
    state.identityView = more;
    if (state.metadata != metadata) {
        state.metadata = metadata;
        SGForEachView(metadata, ^(UIView *view) {
            if ([view isKindOfClass:UILabel.class])
                objc_setAssociatedObject(view, &kListenersSourceKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        });
    }
    if (!identity || !currentConfiguration(state.configuration, state.list, state.aboutPath) ||
        ![state.list isDescendantOfView:page]) [state forgetAbout];
    if (hidden[SGRArtistCellAbout]) return NO;
    return state.aboutPath != nil;
}

static void forgetAboutInList(UICollectionView *list) {
    SGRArtistAboutEvidence *state = objc_getAssociatedObject(SGRArtistPageOf(list), &kListenersPageKey);
    if (state.list == list) [state forgetAbout];
}

static void recordAbout(UICollectionViewCell *cell, UICollectionView *list, NSIndexPath *path, SGRArtistCell kind, CGFloat height) {
    if (!listenersInAbout || hidden[SGRArtistCellAbout] || objc_getAssociatedObject(list, &kListenersUpdatingKey) ||
        objc_getAssociatedObject(list, &kListenersConfiguringKey)) return;
    // The layout can fit provisional/disappearing cells. Only a cell belonging
    // to the live data source certifies that its component is still in the list.
    if (![[list indexPathForCell:cell] isEqual:path]) return;
    SGRArtistAboutEvidence *state = objc_getAssociatedObject(SGRArtistPageOf(list), &kListenersPageKey);
    SGRArtistItemConfiguration *configuration = objc_getAssociatedObject(cell, &kListenersConfigurationKey);
    if (!currentConfiguration(configuration, list, path)) return;
    NSString *identity = state.identityView.accessibilityIdentifier;
    if (![configuration.identity isEqualToString:identity]) return;
    if (kind != SGRArtistCellAbout || height <= 0) {
        if (state.list == list && [state.aboutPath isEqual:path]) [state forgetAbout];
        return;
    }
    if (state.list == list && state.configuration == configuration && [state.aboutPath isEqual:path]) return;
    state.list = list;
    state.configuration = configuration;
    state.aboutPath = path;
    [state.header setNeedsLayout];
}

// Both ordinary requests and snapshot reconfigureItemsWithIdentifiers: use the
// diffable source's provider. Capture before the provider, and require the artist
// and item still to agree after it returns. In particular, a cell first seen at
// layout has no receipt and cannot acquire the new header's identity there.
%group SGRArtistListeners

%hook UICollectionViewDiffableDataSource
- (UICollectionViewCell *)collectionView:(UICollectionView *)list cellForItemAtIndexPath:(NSIndexPath *)path {
    UIView *page = SGRArtistPageOf(list);
    if (!page) return %orig;
    SGRArtistAboutEvidence *state = objc_getAssociatedObject(page, &kListenersPageKey);
    UIView *more = state.identityView;
    if (![more isDescendantOfView:page]) {
        more = SGRFindByIdentifier(page, @"Components.UI.ContextMenuButton*", NULL);
        state.identityView = more;
    }
    NSString *identity = more.accessibilityIdentifier;
    id item = [(UICollectionViewDiffableDataSource *)self itemIdentifierForIndexPath:path];
    if (state.list == list && [state.aboutPath isEqual:path]) [state forgetAbout];
    id configuring = objc_getAssociatedObject(list, &kListenersConfiguringKey);
    objc_setAssociatedObject(list, &kListenersConfiguringKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UICollectionViewCell *cell = %orig;
    SGRArtistItemConfiguration *configuration = nil;
    if ([identity hasPrefix:@"Components.UI.ContextMenuButton-"] &&
        [identity isEqualToString:more.accessibilityIdentifier] &&
        [item isEqual:[(UICollectionViewDiffableDataSource *)self itemIdentifierForIndexPath:path]]) {
        configuration = [SGRArtistItemConfiguration new];
        configuration.source = (UICollectionViewDiffableDataSource *)self;
        configuration.itemIdentifier = item;
        configuration.identity = identity;
    }
    objc_setAssociatedObject(cell, &kListenersConfigurationKey, configuration, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(list, &kListenersConfiguringKey, configuring, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [cell setNeedsLayout];
    return cell;
}
%end

// Text can arrive without another header pass. Watch only metadata labels bound
// above; never copy, parse or truncate Spotify's localized string.
%hook UILabel
- (void)setText:(NSString *)text {
    %orig;
    SGRArtistAboutEvidence *state = objc_getAssociatedObject(self, &kListenersSourceKey);
    [state.header setNeedsLayout];
}
- (void)setAttributedText:(NSAttributedString *)text {
    %orig;
    SGRArtistAboutEvidence *state = objc_getAssociatedObject(self, &kListenersSourceKey);
    [state.header setNeedsLayout];
}
%end

%end // SGRArtistListeners

static SGRArtistCell kindOf(UIView *content, CGFloat height) {
    __block SGRArtistCell kind = SGRArtistCellOther;
    SGForEachView(content, ^(UIView *v) {
        NSString *identifier = v.accessibilityIdentifier;
        if (kind != SGRArtistCellOther || !identifier.length) return;
        if ([identifier isEqualToString:@"Components.UI.MusicVideoShelfHeader"] ||
            [identifier isEqualToString:@"Music-Videos.Video-Card-Carousel"] ||
            [identifier isEqualToString:@"WatchFeedCarouselEntryPointElement"]) kind = SGRArtistCellVideos;
        else if ([identifier isEqualToString:@"Components.UI.PinnedItemUI"]) kind = SGRArtistCellPick;
        else if ([identifier isEqualToString:@"Components.UI.UpcomingReleaseRow"]) kind = SGRArtistCellCountdown;
        else if ([identifier hasPrefix:@"Components.UI.CreatorBiographyCard"]) kind = SGRArtistCellAbout;
        else if ([identifier isEqualToString:@"Components.UI.SectionHeadingHome"]) kind = SGRArtistCellHeading;
    });
    if (kind == SGRArtistCellOther && height <= 16.5 && content.subviews.count <= 1) {
        __block BOOL empty = YES;
        SGForEachView(content, ^(UIView *v) { if (v.accessibilityIdentifier.length) empty = NO; });
        if (empty) kind = SGRArtistCellSpacer;
    }
    return kind;
}

static NSMutableDictionary<NSIndexPath *, NSNumber *> *kindsOf(UICollectionView *list) {
    NSMutableDictionary *kinds = objc_getAssociatedObject(list, &kKindsKey);
    if (!kinds) {
        kinds = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(list, &kKindsKey, kinds, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return kinds;
}

static NSMutableSet<NSIndexPath *> *droppedOf(UICollectionView *list) {
    NSMutableSet *dropped = objc_getAssociatedObject(list, &kDroppedKey);
    if (!dropped) {
        dropped = [NSMutableSet set];
        objc_setAssociatedObject(list, &kDroppedKey, dropped, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return dropped;
}

static UICollectionView *listOf(UIView *cell) {
    for (UIView *v = cell.superview; v; v = v.superview) {
        if ([v isKindOfClass:UICollectionView.class]) return (UICollectionView *)v;
    }
    return nil;
}

static char kPageListKey;

// Bumped each time a different page is found. A cell measured before Spotify names its page keeps a NO only until then.
static NSInteger pagesFound;
static __weak UIView *lastPage;

// Whether the cell is a row of the page's own list: a card inside a carousel is a cell of the same class, and its row
// decides. Worked out once the cell is in a window and kept on it, since a cell never leaves its list nor the list its
// page; every cell of the class asks on every pass, Home's and Search's included. Kept as -1 for YES, or as
// pagesFound when it said NO.
static BOOL onPageList(UICollectionViewCell *cell) {
    NSNumber *known = objc_getAssociatedObject(cell, &kPageListKey);
    if (known.integerValue == -1) return YES;
    if (known && known.integerValue == pagesFound) return NO;
    UICollectionView *list = listOf(cell);
    UIView *page = list && ![listOf(list) isKindOfClass:UICollectionView.class] ? SGRArtistPageOf(cell) : nil;
    if (page && page != lastPage) {
        lastPage = page;
        pagesFound++;
    }
    if (cell.window) objc_setAssociatedObject(cell, &kPageListKey, @(page ? -1 : pagesFound), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return page != nil;
}

// The cell `back` items before `path` in the list, across the end of a section if it has to.
static NSIndexPath *before(UICollectionView *list, NSIndexPath *path, NSInteger back) {
    NSInteger section = path.section, item = path.item - back;
    while (item < 0 && section > 0) {
        section--;
        item += [list numberOfItemsInSection:section];
    }
    return item >= 0 ? [NSIndexPath indexPathForItem:item inSection:section] : nil;
}

// Derive suppression from the current kinds, not from index paths that used to hold hidden content.
// A heading can be measured before or after its content; either order reaches the same answer.
static void recordKind(UICollectionView *list, NSIndexPath *path, SGRArtistCell kind) {
    NSMutableDictionary *kinds = kindsOf(list);
    if (kinds[path] && [kinds[path] integerValue] == kind) return;
    kinds[path] = @(kind);
    NSMutableSet *dropped = [NSMutableSet set];
    for (NSIndexPath *content in kinds) {
        if ([kinds[content] integerValue] < SGRArtistCellVideos) continue;
        [dropped addObject:content];
        NSIndexPath *heading = before(list, content, 1);
        if (!heading || [kinds[heading] integerValue] != SGRArtistCellHeading) continue;
        [dropped addObject:heading];
        NSIndexPath *spacer = before(list, content, 2);
        if (spacer && [kinds[spacer] integerValue] == SGRArtistCellSpacer) [dropped addObject:spacer];
    }
    if ([dropped isEqualToSet:droppedOf(list)]) return;
    objc_setAssociatedObject(list, &kDroppedKey, dropped, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (objc_getAssociatedObject(list, &kInvalidateKey)) return;
    objc_setAssociatedObject(list, &kInvalidateKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UICollectionView *weakList = list;
    dispatch_async(dispatch_get_main_queue(), ^{
        UICollectionView *current = weakList;
        objc_setAssociatedObject(current, &kInvalidateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [current.collectionViewLayout invalidateLayout];
    });
}

// Reloads and insert/delete/move/reload transactions change what every index path means. The layout
// callback covers both ordinary updates and diffable-data-source transactions.
static void forgetKinds(UICollectionView *list) {
    if (!objc_getAssociatedObject(list, &kKindsKey)) return;
    objc_setAssociatedObject(list, &kKindsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(list, &kDroppedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook UICollectionView
- (void)reloadData {
    UICollectionView *list = (UICollectionView *)self;
    forgetAboutInList(list);
    forgetKinds(list);
    BOOL track = listenersInAbout && SGRArtistPageOf(list);
    if (track) objc_setAssociatedObject(list, &kListenersUpdatingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
    if (track) objc_setAssociatedObject(list, &kListenersUpdatingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)setDataSource:(id<UICollectionViewDataSource>)source {
    forgetAboutInList((UICollectionView *)self);
    %orig;
}
%end

%hook UICollectionViewLayout
- (void)prepareForCollectionViewUpdates:(NSArray<UICollectionViewUpdateItem *> *)updates {
    UICollectionView *list = ((UICollectionViewLayout *)self).collectionView;
    forgetAboutInList(list);
    if (listenersInAbout && SGRArtistPageOf(list))
        objc_setAssociatedObject(list, &kListenersUpdatingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    forgetKinds(list);
    %orig;
}
- (void)finalizeCollectionViewUpdates {
    %orig;
    UICollectionView *list = ((UICollectionViewLayout *)self).collectionView;
    if (objc_getAssociatedObject(list, &kListenersUpdatingKey)) {
        objc_setAssociatedObject(list, &kListenersUpdatingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // A surviving cell may not be fitted again after a diffable transaction.
        // Re-read its CURRENT data-source path, never the pre-update position.
        for (UICollectionViewCell *cell in list.visibleCells) [cell setNeedsLayout];
    }
}
%end

static NSMutableSet<NSString *> *sg_loggedMessages;
#define kLogFormat @"redesign artist: %@"

%hook _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    // Only the page's own list: a card inside a carousel is a cell of the same class, and its row decides.
    BOOL page = onPageList(cell) && attributes.indexPath;
    UICollectionView *list = page ? listOf(cell) : nil;
    if (!page) {
        if (objc_getAssociatedObject(cell, &kSettledKey)) SGRRestoreCell(cell, &kSettledKey);
        return %orig;
    }
    UICollectionViewLayoutAttributes *result = %orig;
    NSIndexPath *path = attributes.indexPath;
    UIView *content = cell.contentView.subviews.firstObject ?: cell.contentView;
    SGRArtistCell kind = kindOf(content, result.size.height);
    recordAbout(cell, list, path, kind, result.size.height);
    BOOL hide = kind >= SGRArtistCellVideos && hidden[kind];
    if (kind >= SGRArtistCellVideos && !hide) kind = SGRArtistCellOther;
    recordKind(list, path, kind);

    if (hide) {
        SGLogOnce(&sg_loggedMessages, [dropped[kind] stringByAppendingString:@" dropped from the Music list"], kLogFormat);
    }
    if (!hide && ![droppedOf(list) containsObject:path]) {
        if (objc_getAssociatedObject(cell, &kSettledKey)) SGRRestoreCell(cell, &kSettledKey);
        return result;
    }
    SGRCollapseCell(cell, MAX(1, result.size.height), &kSettledKey);
    result.size = CGSizeMake(result.size.width, 0);
    return result;
}

// The cell's own passes size the content to the cell again.
- (void)layoutSubviews {
    %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    NSNumber *settled = objc_getAssociatedObject(self, &kSettledKey);
    if (settled) SGRCollapseCell(cell, settled.doubleValue, &kSettledKey);
    if (onPageList(cell)) {
        if (listenersInAbout && !hidden[SGRArtistCellAbout]) {
            UICollectionView *list = listOf(cell);
            NSIndexPath *path = [list indexPathForCell:cell];
            if (path) recordAbout(cell, list, path, kindOf(cell.contentView, cell.bounds.size.height), cell.bounds.size.height);
        }
        // What the cell paints over the field -- the "You liked" row, every carousel's collection and the
        // fade Popular's "See more" draws over its last track (device, trees/continuous/3.txt 2026-09-18).
        SGRClearCellPaint(cell);
        clearLikedBadge(cell);
    }
}

- (void)prepareForReuse {
    %orig;
    objc_setAssociatedObject(self, &kListenersConfigurationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (objc_getAssociatedObject(self, &kSettledKey)) SGRRestoreCell((UICollectionViewCell *)self, &kSettledKey);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    hidden[SGRArtistCellVideos] = SGEnabled(SGRKeyArtistHideVideos);
    hidden[SGRArtistCellPick] = SGHidden(SGRKeyArtistHidePick);
    hidden[SGRArtistCellCountdown] = SGHidden(SGRKeyArtistHideCountdown);
    hidden[SGRArtistCellAbout] = SGHidden(SGRKeyArtistHideAbout);
    listenersInAbout = SGFlag(SGRKeyArtistListenersInAbout, NO);
    %init;
    if (listenersInAbout) {
        %init(SGRArtistListeners);
    }
    SGRequireClasses(@[@"_TtC12Element_List18CollectionViewCell"]);
}
