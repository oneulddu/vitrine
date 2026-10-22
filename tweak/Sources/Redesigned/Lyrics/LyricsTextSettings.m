// Drag the three texts of a line into size order, largest first, and tap one to set its size, weight and
// brightness on a page of its own, under a preview of sample lines that keeps its place as the page scrolls.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "LyricsText.h"
#import "LyricsLook.h"
#import "SGRKaraokeView.h"

static const CGFloat kStylePreviewHeight = 230, kStyleCardRadius = 26;

static NSString *percent(double value) {
    return [NSString stringWithFormat:SGL(@"settings.lyricslook.format.percent", @"%.0f%%"), value];
}

#pragma mark - one text's look

@interface SGRLyricsTextStylePage : SGModPage
@end

@implementation SGRLyricsTextStylePage {
    UIView *_header, *_card;
    SGRKaraokeView *_preview;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _header = [UIView new];
    _header.backgroundColor = self.tableView.backgroundColor;   // the rows scroll under it
    _card = [UIView new];
    _card.backgroundColor = SGCardBackground();
    _card.layer.cornerRadius = kStyleCardRadius;
    _card.layer.cornerCurve = kCACornerCurveContinuous;
    _card.clipsToBounds = YES;
    _card.isAccessibilityElement = YES;
    _card.accessibilityLabel = SGL(@"settings.lyricslook.preview.a11y", @"Preview of the lyrics");
    _preview = [[SGRKaraokeView alloc] initWithSampleLines:SGRLyricsSampleLinesWithExtras() length:SGRLyricsSampleLength()];
    _preview.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_card addSubview:_preview];
    [_header addSubview:_card];
    [self.tableView addSubview:_header];
}

// Reset moves every row at once; a slider being dragged is never read back under the finger.
- (void)lookReset {
    [self.tableView reloadData];
    [self refreshVisibility];
}

// The preview takes at most 42% of the room between the bars, and none at all once that leaves it too
// short to read a line, so the rows always have the rest. Scrolling lays the table out again, so it stays on top.
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UITableView *table = self.tableView;
    CGFloat width = table.bounds.size.width, x = table.layoutMargins.left;
    CGFloat inner = width - x - table.layoutMargins.right;
    if (inner <= 0) return;
    CGFloat visible = table.bounds.size.height - table.safeAreaInsets.top - table.safeAreaInsets.bottom - table.contentInset.bottom;
    CGFloat card = MIN(kStylePreviewHeight, floor(visible * .42) - 16);
    if (card < 72) card = 0;
    CGFloat height = card > 0 ? card + 16 : 0;
    _card.hidden = card <= 0;
    _card.frame = CGRectMake(x, 8, inner, card);
    UIEdgeInsets insets = table.contentInset;
    if (insets.top != height) {
        BOOL top = table.contentOffset.y <= 0.5 - table.adjustedContentInset.top;
        insets.top = height;
        table.contentInset = insets;
        table.verticalScrollIndicatorInsets = insets;
        if (top) table.contentOffset = CGPointMake(table.contentOffset.x, -table.adjustedContentInset.top);
    }
    _header.frame = CGRectMake(0, table.contentOffset.y + table.adjustedContentInset.top - height, width, height);
    [table bringSubviewToFront:_header];
}

@end

UIViewController *SGRLyricsTextLookPage(SGRLyricsText text) {
    __block __weak SGRLyricsTextStylePage *owner = nil;
    NSMutableArray<SGModRow *> *rows = [NSMutableArray array];
    [rows addObject:SGSliderRow(SGL(@"settings.lyricstext.style.size.title", @"Size"), nil, 80, 130, 5,
        ^double { return SGRLyricsTextLookOf(text).scale; },
        ^(double value) {
            SGRLyricsTextLook look = SGRLyricsTextLookOf(text);
            look.scale = lround(value);
            SGRSetLyricsTextLook(text, look);
        }, ^NSString *(double value) { return percent(value); })];
    [rows addObject:SGMenuRow(SGL(@"settings.lyricstext.style.weight.title", @"Weight"), SGRLyricsTextWeightNames(),
        ^NSString *{ return SGRLyricsTextWeightNames()[(NSUInteger)SGRLyricsTextLookOf(text).weight]; },
        ^(NSInteger index) {
            SGRLyricsTextLook look = SGRLyricsTextLookOf(text);
            look.weight = index;
            SGRSetLyricsTextLook(text, look);
        })];
    // The lyrics have no brightness of their own: the sung words stay as bright against the waiting ones as ever.
    if (text != SGRLyricsTextLyrics) {
        [rows addObject:SGSliderRow(SGL(@"settings.lyricstext.style.brightness.title", @"Brightness"), nil, 40, 140, 10,
            ^double { return SGRLyricsTextLookOf(text).brightness; },
            ^(double value) {
                SGRLyricsTextLook look = SGRLyricsTextLookOf(text);
                look.brightness = lround(value);
                SGRSetLyricsTextLook(text, look);
            }, ^NSString *(double value) { return percent(value); })];
    }
    SGModRow *reset = SGActionRow(SGL(@"settings.lyricstext.style.reset", @"Reset to default"), nil, ^{
        SGRSetLyricsTextLook(text, SGRLyricsTextLookDefault(text));
        [owner lookReset];
    });
    reset.visible = ^BOOL { return !SGRLyricsTextLookIsDefault(text); };
    NSString *footer = text == SGRLyricsTextLyrics
        ? SGL(@"settings.lyricstext.style.footer.lyrics", @"Size multiplies the size its place in the order gives it. The lyrics keep their brightness, so the words being sung stand out as before.")
        : SGL(@"settings.lyricstext.style.footer.other", @"Size multiplies the size its place in the order gives it. 100% is the usual look.");
    SGRLyricsTextStylePage *page = [[SGRLyricsTextStylePage alloc] initWithTitle:SGRLyricsTextName(text) intro:nil
        sections:@[SGNotedSection(nil, rows, footer), SGSection(nil, @[reset])] footer:nil];
    owner = page;
    return page;
}

#pragma mark - the order

@interface SGRLyricsTextPage : SGPage
@end

@implementation SGRLyricsTextPage {
    NSMutableArray<NSNumber *> *_order;
    UIView *_footer;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = SGL(@"settings.lyricstext.title", @"Text sizes");
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _order = [SGRLyricsTextOrder() mutableCopy];
    self.tableView.editing = YES;
    self.tableView.allowsSelectionDuringEditing = YES;
    _footer = SGNote([@[SGL(@"settings.lyricstext.footer", @"Pronunciation and translation are turned on from the button in the lyrics' corner."),
                        SGL(@"settings.lyricstext.footer.style", @"Tap one to set its size, weight and brightness.")] componentsJoinedByString:@" "]);
    self.tableView.tableFooterView = _footer;
}

// Coming back from a text's own page, its line here reads what was set there.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _footer, 16, 24);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_order.count;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    return SGSectionHeader(table, SGL(@"settings.lyricstext.order.header", @"Largest first"));
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return SGSectionHeaderHeight();
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"text");
    SGRLyricsText text = _order[(NSUInteger)path.row].integerValue;
    NSArray<NSString *> *sizes = @[SGL(@"settings.lyricstext.size.choice.largest", @"Largest"), SGL(@"settings.lyricstext.size.choice.smaller", @"Smaller"), SGL(@"settings.lyricstext.size.choice.smallest", @"Smallest")];
    NSString *symbol = text == SGRLyricsTextLyrics ? @"music.mic" : text == SGRLyricsTextPronunciation ? @"character.phonetic" : @"character.bubble";
    // Its place's size, then how the text's own page sets it.
    SGRLyricsTextLook look = SGRLyricsTextLookOf(text);
    NSMutableArray<NSString *> *summary = [NSMutableArray arrayWithObjects:sizes[MIN((NSUInteger)path.row, sizes.count - 1)],
                                           percent(look.scale), SGRLyricsTextWeightNames()[(NSUInteger)look.weight], nil];
    if (text != SGRLyricsTextLyrics) {
        [summary addObject:[NSString stringWithFormat:SGL(@"settings.lyricstext.summary.brightness", @"Brightness %@"), percent(look.brightness)]];
    }
    SGFillCell(cell, SGRLyricsTextName(text), [summary componentsJoinedByString:@" · "], nil, symbol);
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.editingAccessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.accessibilityHint = SGL(@"settings.lyricstext.row.hint.a11y", @"Opens its size, weight and brightness");
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    // Pushed onto this page's own stack, as SGModPage pushes the pages its rows open.
    [self.navigationController pushViewController:SGRLyricsTextLookPage(_order[(NSUInteger)path.row].integerValue) animated:YES];
}

- (BOOL)tableView:(UITableView *)table canMoveRowAtIndexPath:(NSIndexPath *)path {
    return YES;
}

- (BOOL)tableView:(UITableView *)table canEditRowAtIndexPath:(NSIndexPath *)path {
    return YES;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)table editingStyleForRowAtIndexPath:(NSIndexPath *)path {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)table shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)path {
    return NO;
}

- (void)tableView:(UITableView *)table moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSNumber *text = _order[(NSUInteger)from.row];
    [_order removeObjectAtIndex:(NSUInteger)from.row];
    [_order insertObject:text atIndex:(NSUInteger)to.row];
    SGRSetLyricsTextOrder(_order);
    [table reloadData];   // the sizes under the names have all moved
}

@end

SGModRow *SGRLyricsTextSizesRow(void) {
    return SGPageRow(SGL(@"settings.lyricstext.row.title", @"Text sizes"), ^UIViewController *{ return [SGRLyricsTextPage new]; });
}
