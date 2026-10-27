// Album redesign: the track rows on the field, the way the Music app has them -- no surface of their own
// and a hairline from the text's edge between one row and the next.
//
// Tree (trees/clean/album/03.txt:524-575): every row of the page is an Element_List.CollectionViewCell
// holding an Encore.ListRow, id=Components.UI.RetrievalRowElementUI, with the title
// (EncoreConsumerMobile.View.Granular.Title), the artists under it (…Granular.Subtitle) and, at the
// trailing edge, Components.UI.ContextMenuButton. An album row carries no artwork -- every track on the
// page shares the cover the header is already showing -- so the hairline runs from the page's own margin,
// where the text starts.
//
// The row's paint is cleared here rather than left to the Kit's repaint hook, which only hears about a
// color when Spotify sets it and not when a reused cell already carries one.
//
// Spotify's type and its spacing are left alone: the row is 56pt for a title of 13pt, and a larger font of
// the Kit's would be cut off by the box the element framework measured for it.
//
// **The artist line, where it only repeats the album's.** The Music app shows a track's title alone on a
// standard album, so the line goes where AlbumCredits.m finds it says nothing the header does not. It goes by
// alpha on the Subtitle wrapper: Encore sets its inner label's alpha again later, `hidden` inside its stacks
// crashes, and the row keeps the height Spotify measured for it. The title is moved down to the middle of the
// row by a translation. The explicit badge is a sibling of the line, not inside it, so it is drawn again as a
// picture after the title's text, 4pt on, and the badge itself goes by alpha; the title is narrowed by the
// badge's room so a long one cannot run under it or under ⋯. Right to left, all of it the other way round.
// The row's own accessibility label still names the artists and says explicit; the picture is not an element.
//
// **Play counts.** A track played in Listening stats says how many times, "12 plays", in the secondary color on
// the row's middle just before ⋯, as small as the row's own type allows; none for a track never played. The
// count is the album's title and the row's title matched in the log (AlbumPlays.m), so the rows are laid out
// again when the header's title arrives and when the counts change. The title and the artist line are narrowed
// so neither runs under it. This is done before the artist line's change, which then measures the narrowed
// title, and put back after it. That is the In the row place of the Albums page's Play counts; In menu the row shows
// none, and its ⋯ tells AlbumPlaysMenu.x which track the sheet it opens is for.
//
// Everything changed is put back at the start of the cell's next pass and when the cell is prepared for reuse,
// which also asks for a pass: Spotify can show a cached row again at the same size without one, and the last
// row's state would stay on it.
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Album.h"

// Under the text rather than the whole row, as the Music app draws it; the trailing end clears the page
// margin.
static const CGFloat kHairline = 0.5;
// Between the end of the title's text and the badge drawn after it.
static const CGFloat kBadgeGap = 4;
// Between the play count and ⋯'s box, whose glyph is inset in it already, and between the text and the count.
static const CGFloat kCountGap = 2, kCountTextGap = 8;

static char kRowKey, kSubtitleKey, kLineKey, kTitleKey, kBadgeKey, kArtistKey, kChangeKey;
static char kAlbumKey, kMenuKey, kCountKey, kCountChangeKey;
static NSMutableSet<NSString *> *sg_loggedMenus;

static void clearSurface(UIView *view) {
    UIColor *color = view.backgroundColor;
    if (color && SGIsBaseSurface(color.CGColor)) view.backgroundColor = UIColor.clearColor;
}

static void applyHairline(UIView *row) {
    CALayer *line = objc_getAssociatedObject(row, &kLineKey);
    if (!line) {
        line = [CALayer layer];
        line.zPosition = 1;
        objc_setAssociatedObject(row, &kLineKey, line, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    line.backgroundColor = SGRHairline().CGColor;
    if (line.superlayer != row.layer) [row.layer addSublayer:line];
    CGRect bounds = row.bounds;
    CGRect frame = CGRectMake(SGRSideMargin, bounds.size.height - kHairline,
                              MAX(0, bounds.size.width - 2 * SGRSideMargin), kHairline);
    if (CGRectEqualToRect(line.frame, frame)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    line.frame = frame;
    [CATransaction commit];
}

#pragma mark - the artist line

// What a row's credit change touched, and what each was before, to be put back.
@interface SGRCreditChange : NSObject
@property (nonatomic, weak) UIView *subtitle, *badge;
@property (nonatomic, weak) UILabel *title;
@property (nonatomic) CGFloat subtitleAlpha, badgeAlpha;
@property (nonatomic) CGRect titleFrame, narrowFrame;
@property (nonatomic) CGAffineTransform shift;
@property (nonatomic, strong) UIImageView *drawnBadge;
@end

@implementation SGRCreditChange
@end

static BOOL hidesCredits(void) {
    static NSInteger on = -1;
    if (on < 0) on = SGEnabled(SGRKeyAlbumHideTrackArtists);
    return on;
}

// The one label under `view`, itself included, with text in it; nil for none or for more than one.
static UILabel *onlyLabel(UIView *view) {
    __block UILabel *found = nil;
    __block NSUInteger count = 0;
    SGForEachView(view, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class]) return;
        NSString *text = [((UILabel *)v).text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!text.length) return;
        found = (UILabel *)v;
        count++;
    });
    return count == 1 ? found : nil;
}

// The badge as it draws, rendered the moment before it goes: an unplayable row's is grayed, so it is not cached.
static UIImage *pictureOf(UIView *badge) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat formatForTraitCollection:badge.traitCollection];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:badge.bounds.size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [badge.layer renderInContext:context.CGContext];
    }];
}

// Puts back what the last change took. YES when there was one.
static BOOL restoreCredit(UIView *cell) {
    SGRCreditChange *change = objc_getAssociatedObject(cell, &kChangeKey);
    if (!change) return NO;
    objc_setAssociatedObject(cell, &kChangeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [change.drawnBadge removeFromSuperview];
    // The transform before the frame, which is meaningless under one. Each only where it is still this change's:
    // a pass of Spotify's since may have put its own there.
    UILabel *title = change.title;
    if (title && CGAffineTransformEqualToTransform(title.transform, change.shift)) title.transform = CGAffineTransformIdentity;
    if (title && !CGRectIsNull(change.narrowFrame) && CGRectEqualToRect(title.frame, change.narrowFrame)) title.frame = change.titleFrame;
    if (change.subtitle.alpha == 0) change.subtitle.alpha = change.subtitleAlpha;
    if (change.badge.alpha == 0) change.badge.alpha = change.badgeAlpha;
    return YES;
}

// The rows on screen were laid out against what the header said before; the rest are laid out as they come.
static void layOutRowsAgain(UIView *page) {
    SGForEachView(page, ^(UIView *v) {
        if ([v isKindOfClass:%c(_TtC12Element_List18CollectionViewCell)]) [v setNeedsLayout];
    });
}

void SGRAlbumSetArtist(UIView *view, NSString *artist) {
    UIView *page = SGRAlbumPageOf(view);
    NSString *known = objc_getAssociatedObject(page, &kArtistKey);
    if (!page || known == artist || [known isEqualToString:artist]) return;
    objc_setAssociatedObject(page, &kArtistKey, artist, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (hidesCredits()) layOutRowsAgain(page);
}

static void applyCredit(UIView *cell, UIView *row, UIView *page) {
    NSString *album = objc_getAssociatedObject(page, &kArtistKey);
    if (!album) return;
    // The content's own pass first: a new row has no size in its text before it.
    [((UICollectionViewCell *)cell).contentView layoutIfNeeded];
    UIView *subtitle = SGRFindByIdentifier(row, @"EncoreConsumerMobile.View.Granular.Subtitle", &kSubtitleKey);
    UILabel *title = onlyLabel(SGRFindByIdentifier(row, @"EncoreConsumerMobile.View.Granular.Title", &kTitleKey));
    UILabel *artist = onlyLabel(subtitle);
    if (!title || !artist || !SGRCreditRepeatsAlbum(album, artist.text, title.text)) return;
    // Mid animation the title's frame is not where it is going.
    if (!CGAffineTransformIsIdentity(title.transform) || title.layer.animationKeys.count) return;

    UIView *badge = SGRFindByIdentifier(row, @"Components.UI.ExplicitIcon", &kBadgeKey);
    if (badge && (badge.hidden || badge.alpha < 0.01 || CGRectIsEmpty(badge.bounds))) badge = nil;
    CGRect frame = title.frame;
    CGFloat room = badge ? badge.bounds.size.width + kBadgeGap : 0;
    if (frame.size.width - room < title.font.lineHeight) return;
    NSTextAlignment alignment = title.textAlignment;
    BOOL rtl = title.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    BOOL textAtRight = alignment == NSTextAlignmentRight || (alignment == NSTextAlignmentNatural && rtl);
    CGFloat narrowWidth = frame.size.width - room;
    CGSize text = [title textRectForBounds:CGRectMake(0, 0, narrowWidth, CGFLOAT_MAX) limitedToNumberOfLines:title.numberOfLines].size;
    // ponytail: one line only. A wrapped title's last line ends somewhere this does not measure, so its badge
    // would be placed against the widest line; such a row keeps its artist line instead.
    if (badge && (alignment == NSTextAlignmentCenter || text.height > title.font.lineHeight * 1.5)) return;

    SGRCreditChange *change = [SGRCreditChange new];
    change.subtitle = subtitle;
    change.subtitleAlpha = subtitle.alpha;
    change.title = title;
    change.titleFrame = frame;
    change.narrowFrame = CGRectNull;
    subtitle.alpha = 0;
    if (badge) {
        CGRect narrow = frame;
        narrow.size.width = narrowWidth;
        if (rtl) narrow.origin.x += room;
        title.frame = narrow;
        change.narrowFrame = narrow;
    }
    CGFloat scale = row.window.screen.scale ?: UIScreen.mainScreen.scale;
    CGPoint centre = [title.superview convertPoint:title.center toView:row];
    CGFloat dy = round((CGRectGetMidY(row.bounds) - centre.y) * scale) / scale;
    change.shift = CGAffineTransformMakeTranslation(0, dy);
    title.transform = change.shift;

    if (badge) {
        UIImageView *drawn = [[UIImageView alloc] initWithImage:pictureOf(badge)];
        drawn.userInteractionEnabled = NO;
        drawn.isAccessibilityElement = NO;
        CGSize size = badge.bounds.size;
        CGFloat textWidth = MIN(ceil(text.width), narrowWidth);
        CGFloat x = textAtRight ? narrowWidth - textWidth - kBadgeGap - size.width : textWidth + kBadgeGap;
        CGRect inTitle = CGRectMake(x, (title.bounds.size.height - size.height) / 2, size.width, size.height);
        // Through the title, whose transform the conversion takes along.
        drawn.frame = [title convertRect:inTitle toView:row];
        [row addSubview:drawn];
        change.drawnBadge = drawn;
        change.badge = badge;
        change.badgeAlpha = badge.alpha;
        badge.alpha = 0;
    }
    objc_setAssociatedObject(cell, &kChangeKey, change, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    static BOOL logged;
    if (!logged) {
        logged = YES;
        SGLog(@"redesign album: a track's artist line hidden as the album's, badge %@", badge ? @"moved up" : @"none");
    }
}

#pragma mark - play counts

static SGRAlbumPlayCountsPlace countsPlace(void) {
    static NSInteger place = -1;
    if (place < 0) place = SGRAlbumPlayCountsWhere();
    return (SGRAlbumPlayCountsPlace)place;
}

// The album pages that have had a title, to lay out again when the counts change.
static NSHashTable<UIView *> *countedPages(void) {
    static NSHashTable<UIView *> *pages;
    if (!pages) pages = [NSHashTable weakObjectsHashTable];
    return pages;
}

void SGRAlbumSetTitle(UIView *view, NSString *title) {
    UIView *page = SGRAlbumPageOf(view);
    NSString *known = objc_getAssociatedObject(page, &kAlbumKey);
    if (!page || countsPlace() == SGRAlbumPlayCountsOff || known == title || [known isEqualToString:title]) return;
    objc_setAssociatedObject(page, &kAlbumKey, title, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (countsPlace() == SGRAlbumPlayCountsInMenu) {
        // No row asks for a count before a ⋯ is touched; the first ask starts reading the log, so it is read by then.
        SGRAlbumPlayCount(title, nil);
        return;
    }
    [countedPages() addObject:page];
    layOutRowsAgain(page);
}

// In menu: a row's ⋯ says which track the sheet it opens is for (AlbumPlaysMenu.x) as it sends its action, before
// Spotify's runs: a finger's tap, VoiceOver's activation, Full Keyboard Access and Switch Control all go through
// UIControl's sendAction, where a touch-down target would miss every one but the finger. A row's pass flags its ⋯
// as watched, so every other control pays one associated-object read. The cell holds the ⋯ it flagged and takes the
// flag back as it is prepared for reuse or laid out as anything but an album's track row; and the action checks the
// row again, so a ⋯ that is no longer an album track's leaves whatever mark there is alone.
static char kWatchedKey, kWatchedMenuKey;

static void unwatch(UIView *cell) {
    UIView *menu = objc_getAssociatedObject(cell, &kWatchedMenuKey);
    if (!menu) return;
    objc_setAssociatedObject(menu, &kWatchedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(cell, &kWatchedMenuKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UIView *cellOf(UIView *view) {
    Class cellClass = %c(_TtC12Element_List18CollectionViewCell);
    for (UIView *v = view; v; v = v.superview) {
        if ([v isKindOfClass:cellClass]) return v;
    }
    return nil;
}

static void markIfWatched(UIControl *control) {
    if (!objc_getAssociatedObject(control, &kWatchedKey)) return;
    UICollectionViewCell *cell = (UICollectionViewCell *)cellOf(control);
    UIView *page = cell ? SGRAlbumPageOf(cell) : nil;
    NSString *album = page ? objc_getAssociatedObject(page, &kAlbumKey) : nil;
    UIView *row = control.superview;
    while (row && ![row.accessibilityIdentifier hasPrefix:@"Components.UI.RetrievalRow"]) row = row.superview;
    UILabel *title = onlyLabel(SGRFindByIdentifier(row, @"EncoreConsumerMobile.View.Granular.Title", &kTitleKey));
    BOOL eligible = cell && objc_getAssociatedObject(cell, &kWatchedMenuKey) == control
        && SGRIsTrackContent(cell.contentView.subviews.firstObject) && album.length && title.text.length
        && [control.accessibilityIdentifier hasPrefix:@"Components.UI.ContextMenuButton"] && [row isDescendantOfView:cell];
    if (!eligible) {
        objc_setAssociatedObject(control, &kWatchedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (cell && objc_getAssociatedObject(cell, &kWatchedMenuKey) == control) unwatch(cell);
        return;
    }
    SGRAlbumPlaysMarkMenu(album, title.text);
}

%group SGRAlbumMenuActions
%hook UIControl
- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    markIfWatched(self);
    %orig;
}

- (void)sendAction:(UIAction *)action {
    markIfWatched(self);
    %orig;
}
%end
%end

static void watchMenu(UIView *cell, UIView *row) {
    UIView *menu = SGRFindByIdentifier(row, @"Components.UI.ContextMenuButton*", &kMenuKey);
    if (!menu) return;
    if (![menu isKindOfClass:UIControl.class]) {
        SGLogOnce(&sg_loggedMenus, NSStringFromClass(menu.class), @"redesign album: a track's ⋯ is a %@, not a control: its plays stay off its sheet");
        return;
    }
    // The cell holds its own descendant: no cycle.
    objc_setAssociatedObject(menu, &kWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(cell, &kWatchedMenuKey, menu, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// What a row's count narrowed, each label's frame before and after, to be put back.
@interface SGRCountChange : NSObject
@property (nonatomic, strong) UILabel *count;
@property (nonatomic, strong) NSMapTable<UILabel *, NSArray<NSValue *> *> *frames;
@end

@implementation SGRCountChange
@end

static BOOL restoreCount(UIView *cell) {
    SGRCountChange *change = objc_getAssociatedObject(cell, &kCountChangeKey);
    if (!change) return NO;
    objc_setAssociatedObject(cell, &kCountChangeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [change.count removeFromSuperview];
    // Only where the frame is still this change's: a pass of Spotify's since may have put its own there.
    for (UILabel *label in change.frames) {
        NSArray<NSValue *> *frames = [change.frames objectForKey:label];
        if (CGRectEqualToRect(label.frame, frames[1].CGRectValue)) label.frame = frames[0].CGRectValue;
    }
    return YES;
}

static void applyCount(UIView *cell, UIView *row, UIView *page) {
    NSString *album = objc_getAssociatedObject(page, &kAlbumKey);
    if (!album) return;
    [((UICollectionViewCell *)cell).contentView layoutIfNeeded];
    UILabel *title = onlyLabel(SGRFindByIdentifier(row, @"EncoreConsumerMobile.View.Granular.Title", &kTitleKey));
    if (!title) return;
    NSUInteger plays = SGRAlbumPlayCount(album, title.text);
    if (!plays) return;
    UIView *menu = SGRFindByIdentifier(row, @"Components.UI.ContextMenuButton*", &kMenuKey);
    if (!menu || menu.alpha < 0.01 || CGRectIsEmpty(menu.bounds)) return;
    if (!CGAffineTransformIsIdentity(title.transform) || title.layer.animationKeys.count) return;

    UILabel *count = objc_getAssociatedObject(cell, &kCountKey);
    if (!count) {
        count = [UILabel new];
        count.userInteractionEnabled = NO;
        count.isAccessibilityElement = NO;
        objc_setAssociatedObject(cell, &kCountKey, count, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // The row is measured for Spotify's fixed type, so the count grows with Dynamic Type only up to Large.
    count.font = SGMonospacedDigitsFont(SGCategoryCappedFont(UIFontTextStyleCaption1, UIFontWeightRegular, UIContentSizeCategoryLarge));
    count.textColor = SGRSecondary();
    count.text = SGRAlbumPlaysText(plays);
    CGSize size = [count sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    size = CGSizeMake(ceil(size.width), ceil(size.height));

    BOOL rtl = row.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGRect menuFrame = [menu.superview convertRect:menu.frame toView:row];
    CGFloat x = rtl ? CGRectGetMaxX(menuFrame) + kCountGap : CGRectGetMinX(menuFrame) - kCountGap - size.width;
    CGFloat scale = row.window.screen.scale ?: UIScreen.mainScreen.scale;
    CGFloat y = round((CGRectGetMidY(row.bounds) - size.height / 2) * scale) / scale;
    CGRect frame = CGRectMake(x, y, size.width, size.height);
    CGFloat limit = rtl ? CGRectGetMaxX(frame) + kCountTextGap : CGRectGetMinX(frame) - kCountTextGap;

    // The title and every label of the artist line kept clear of the count; a row with no room for the title
    // goes without it.
    NSMutableArray<UILabel *> *labels = [NSMutableArray arrayWithObject:title];
    SGForEachView(SGRFindByIdentifier(row, @"EncoreConsumerMobile.View.Granular.Subtitle", &kSubtitleKey), ^(UIView *v) {
        if ([v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) [labels addObject:(UILabel *)v];
    });
    NSMapTable<UILabel *, NSArray<NSValue *> *> *frames = [NSMapTable weakToStrongObjectsMapTable];
    for (UILabel *label in labels) {
        CGRect inRow = [label.superview convertRect:label.frame toView:row];
        CGFloat over = rtl ? limit - CGRectGetMinX(inRow) : CGRectGetMaxX(inRow) - limit;
        if (over <= 0) continue;
        CGRect narrow = label.frame;
        narrow.size.width -= over;
        if (rtl) narrow.origin.x += over;
        if (label == title && narrow.size.width < title.font.lineHeight * 3) return;
        [frames setObject:@[[NSValue valueWithCGRect:label.frame], [NSValue valueWithCGRect:narrow]] forKey:label];
    }

    SGRCountChange *change = [SGRCountChange new];
    change.count = count;
    change.frames = frames;
    for (UILabel *label in frames) label.frame = [frames objectForKey:label][1].CGRectValue;
    count.frame = frame;
    [row addSubview:count];
    objc_setAssociatedObject(cell, &kCountChangeKey, change, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    static BOOL logged;
    if (!logged) {
        logged = YES;
        SGLog(@"redesign album: a track's plays shown, %lu, %lu label(s) narrowed", (unsigned long)plays, (unsigned long)frames.count);
    }
}

#pragma mark - the rows

static void applyRow(UIView *cell, UIView *page) {
    clearSurface(cell);
    UIView *row = SGRFindByIdentifier(cell, @"Components.UI.RetrievalRow*", &kRowKey);
    if (!row) return;
    // The row, and every box the element framework wraps it in on the way back up to the cell.
    for (UIView *v = row; v; v = v.superview) {
        clearSurface(v);
        if (v == cell) break;
    }

    UIView *subtitle = SGRFindByIdentifier(row, @"EncoreConsumerMobile.View.Granular.Subtitle", &kSubtitleKey);
    SGForEachView(subtitle, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class]) return;
        UILabel *label = (UILabel *)v;
        if (![label.textColor isEqual:SGRSecondary()]) label.textColor = SGRSecondary();
    });

    applyHairline(row);
    if (countsPlace() == SGRAlbumPlayCountsInRow) applyCount(cell, row, page);
    else if (countsPlace() == SGRAlbumPlayCountsInMenu) watchMenu(cell, row);
    if (hidesCredits()) applyCredit(cell, row, page);
}

#pragma mark - the cells

%hook _TtC12Element_List18CollectionViewCell
- (void)layoutSubviews {
    // In the reverse of the order they were made: the artist line's change measured the narrowed title.
    restoreCredit((UIView *)self);
    restoreCount((UIView *)self);
    // Flagged again below while it is still an album's track row.
    unwatch((UIView *)self);
    %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    if (!SGRIsTrackContent(cell.contentView.subviews.firstObject)) return;
    UIView *page = SGRAlbumPageOf(cell);
    if (page) applyRow(cell, page);
}

- (void)prepareForReuse {
    %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    unwatch(cell);
    BOOL changed = restoreCredit(cell);
    changed = restoreCount(cell) || changed;
    if (changed || SGRIsTrackContent(cell.contentView.subviews.firstObject)) [cell setNeedsLayout];
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    if (countsPlace() == SGRAlbumPlayCountsInMenu) %init(SGRAlbumMenuActions);
    if (countsPlace() == SGRAlbumPlayCountsInRow) {
        // Posted on the main thread (AlbumPlays.m).
        [NSNotificationCenter.defaultCenter addObserverForName:SGRAlbumPlayCountsDidChangeNotification object:nil
                                                         queue:nil usingBlock:^(NSNotification *note) {
            for (UIView *page in countedPages().allObjects) layOutRowsAgain(page);
        }];
    }
    SGRequireClasses(@[@"_TtC12Element_List18CollectionViewCell"]);
}
