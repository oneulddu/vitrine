// The redesign's Library page: Compact library (Library.h), read at launch. It leads with a preview of Your Library
// (Kit/SGRPagePreview.h) that follows the switch: the chips under the title go, and the menu's glyph comes in before
// the avatar. Its own parts read from the leading edge, mirrored right to left as the header is.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "Redesigned/Kit/SGRPagePreview.h"
#import "Library.h"

// The title row: the large title, the menu's glyph and the avatar, at the sizes of the Kit's title row
// (SGRPreviewAddTitle), which has no place for a glyph before the avatar.
static const CGFloat kTitleTop = 8, kTitleRow = 34, kTitleFont = 22, kAvatar = 26, kMenuGlyph = 16, kMenuGap = 14;
// The chips: four glass capsules, a bar for each one's name.
static const CGFloat kChip = 24, kChipGap = 6, kChipPad = 10, kChipBar = 6;
static const CGFloat kChipWidths[] = {62, 66, 54, 52};
static const NSUInteger kChipCount = sizeof(kChipWidths) / sizeof(kChipWidths[0]);
// The sort row: the sort glyph and a bar for its order at the leading edge, the view's glyph at the trailing one.
static const CGFloat kSortRow = 22, kSortGlyph = 12, kSortBar = 7, kSortBarWidth = 48, kSortGap = 6;
// The list: rows of covers, the first in the accent color as Spotify draws what is playing.
static const NSUInteger kRows = 5, kFirstCover = 2;

// `frame`, laid out from the left of a span `width` wide, put where it reads from the leading edge: mirrored in a
// right-to-left language, as Your Library's header is (LibraryHeader.x).
static CGRect leading(UIView *view, CGRect frame, CGFloat width) {
    if (view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft) frame.origin.x = width - CGRectGetMaxX(frame);
    return frame;
}

static SGRPagePreview *libraryPreview(NSString *title, NSString *menuName, NSString *chipsName, NSString *sortName) {
    SGRPagePreview *card = [[SGRPagePreview alloc] initWithLabel:SGL(@"settings.library.preview.a11y", @"Preview of Your Library")];

    // Where the menu's glyph goes on a page `width` wide, read left to right: before the avatar, on the title row's
    // middle.
    CGRect (^menuFrame)(CGFloat, CGFloat) = ^CGRect(CGFloat width, CGFloat unit) {
        CGFloat middle = (kTitleTop + kTitleRow / 2) * unit, glyph = kMenuGlyph * unit;
        return CGRectMake(width - SGRPagePreviewMargin - (kAvatar + kMenuGap) * unit - glyph, middle - glyph / 2, glyph, glyph);
    };
    __block BOOL compact = NO;
    UILabel *label = SGRPreviewLabel(title, SGRPrimary());
    UIView *avatar = SGRPreviewAvatar();
    UIView *titlePart = [card addPartWithLayout:^CGFloat(UIView *part, CGFloat width, CGFloat unit) {
        CGFloat top = kTitleTop * unit, row = kTitleRow * unit, middle = top + row / 2, side = kAvatar * unit;
        CGRect face = CGRectMake(width - SGRPagePreviewMargin - side, middle - side / 2, side, side);
        avatar.frame = leading(part, face, width);
        label.font = SGRPreviewFont(kTitleFont, UIFontWeightBold, unit);
        CGFloat end = compact ? CGRectGetMinX(menuFrame(width, unit)) : CGRectGetMinX(face);
        label.frame = leading(part, CGRectMake(SGRPagePreviewMargin, top, MAX(0, end - kMenuGap * unit - SGRPagePreviewMargin), row), width);
        return top + row;
    }];
    for (UIView *view in @[label, avatar]) [titlePart addSubview:view];
    titlePart.accessibilityLabel = title;

    // The menu's glyph over the title row, a name of its own for VoiceOver.
    UIImageView *glyph = SGRPreviewSymbol(@"line.3.horizontal.decrease", SGRPrimary());
    UIView *menu = [card addOverlayWithLayout:^CGRect(UIView *overlay, CGSize page, CGFloat unit) {
        CGRect frame = leading(overlay, menuFrame(page.width, unit), page.width);
        glyph.frame = (CGRect){CGPointZero, frame.size};
        return frame;
    }];
    [menu addSubview:glyph];
    menu.accessibilityLabel = menuName;

    NSMutableArray<UIView *> *chips = [NSMutableArray array];
    UIView *chipsPart = [card addPartWithLayout:^CGFloat(UIView *part, CGFloat width, CGFloat unit) {
        CGFloat height = kChip * unit, x = SGRPagePreviewMargin;
        for (NSUInteger i = 0; i < chips.count; i++) {
            UIView *chip = chips[i];
            CGFloat chipWidth = kChipWidths[i] * unit;
            chip.frame = leading(part, CGRectMake(x, 0, chipWidth, height), width);
            chip.layer.cornerRadius = height / 2;
            chip.subviews.firstObject.frame = CGRectMake(kChipPad * unit, (height - kChipBar * unit) / 2, chipWidth - 2 * kChipPad * unit, kChipBar * unit);
            x += chipWidth + kChipGap * unit;
        }
        return height;
    }];
    for (NSUInteger i = 0; i < kChipCount; i++) {
        UIView *chip = SGRPreviewGlass();
        [chip addSubview:SGRPreviewBar(SGRSecondary())];
        [chipsPart addSubview:chip];
        [chips addObject:chip];
    }
    chipsPart.accessibilityLabel = chipsName;

    UIImageView *sortGlyph = SGRPreviewSymbol(@"arrow.up.arrow.down", SGRSecondary());
    UIView *sortBar = SGRPreviewBar(SGRSecondary());
    UIImageView *viewGlyph = SGRPreviewSymbol(@"square.grid.2x2", SGRSecondary());
    UIView *sortPart = [card addPartWithLayout:^CGFloat(UIView *part, CGFloat width, CGFloat unit) {
        CGFloat height = kSortRow * unit, glyph = kSortGlyph * unit, middle = height / 2;
        CGRect sortFrame = CGRectMake(SGRPagePreviewMargin, middle - glyph / 2, glyph, glyph);
        sortGlyph.frame = leading(part, sortFrame, width);
        sortBar.frame = leading(part, CGRectMake(CGRectGetMaxX(sortFrame) + kSortGap * unit, middle - kSortBar * unit / 2, kSortBarWidth * unit, kSortBar * unit), width);
        viewGlyph.frame = leading(part, CGRectMake(width - SGRPagePreviewMargin - glyph, middle - glyph / 2, glyph, glyph), width);
        return height;
    }];
    for (UIView *view in @[sortGlyph, sortBar, viewGlyph]) [sortPart addSubview:view];
    sortPart.accessibilityLabel = sortName;

    SGRPreviewAddTracks(card, kRows, YES, kFirstCover);
    [card addTabBarShowing:SGRPreviewTabLibrary];

    card.state = ^id<NSObject> {
        return @(SGFlag(SGRKeyLibraryHideChips, NO));
    };
    card.apply = ^(SGRPagePreview *preview, NSNumber *state) {
        compact = state.boolValue;
        [preview setPart:chipsPart shown:!compact];
        [preview setPart:menu shown:compact];
        [preview revealPart:titlePart];
    };
    return card;
}

UIViewController *SGRLibrarySettingsPage(void) {
    NSString *title = SGL(@"settings.library.preview.title", @"Your Library");
    NSString *menuName = SGL(@"settings.library.preview.menu", @"Sort and view menu");
    NSString *chipsName = SGL(@"settings.library.preview.chips", @"Filter chips");
    NSString *sortName = SGL(@"settings.library.preview.sort_row", @"Sort order and view");
    return SGRPagePreviewPage(SGL(@"settings.library.title", @"Library"), libraryPreview(title, menuName, chipsName, sortName), SGRestartNote, @[
        SGNotedSection(nil, @[
            SGOptionRow(SGL(@"settings.library.compact.title", @"Compact library"),
                        SGL(@"settings.library.compact.subtitle", @"Hides the filter chips under the title. A menu beside it sorts, switches between list and grid, and clears a filter, through Spotify's own controls."),
                        SGRKeyLibraryHideChips),
        ], SGL(@"settings.library.compact.note", @"Folders keep their chips. Whenever the menu cannot reach Spotify's controls, the chips stay.")),
    ]);
}
