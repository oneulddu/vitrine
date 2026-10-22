// The pages are built by their rows' blocks as they are opened, so nothing lists every row ahead of time:
// the first letter typed builds the pages the page's rows open, and theirs, once per visit, and reads their
// rows. A row that shows only under some other setting (SGModRow.visible) is left out while it would not show.
// Building a page is cheap: it makes rows, and a row asks for its value only once its page is on screen.
#import "SGSettingsSearch.h"
#import "SGPageStyle.h"
#import "Core/SGCore.h"

static const NSUInteger kDepth = 2;       // the page itself, then two levels of pages under it
static const NSUInteger kMostHits = 60;
static char kSearchKey;

@interface SGSettingsHit : NSObject
@property (nonatomic, copy) NSString *title, *subtitle;
@property (nonatomic, copy) NSArray<NSString *> *trail;   // the pages above the row, from the searched page's row down
@property (nonatomic, copy) NSString *symbol;             // the tile of the searched page's row the trail starts from
@property (nonatomic, strong) UIColor *tint;
// What picking the hit opens: the page the row sits on (nil for the searched page itself), or the row's own
// page when `opens`.
@property (nonatomic, copy) UIViewController *(^open)(void);
@property (nonatomic) BOOL opens;
@property (nonatomic, copy) NSString *folded, *foldedTitle;
@property (nonatomic, copy) NSString *initials, *initialsTitle;   // the folded text with each syllable as its initial
@end

@implementation SGSettingsHit
@end

static NSString *fold(NSString *text) {
    return [text ?: @"" stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch
                                            locale:NSLocale.currentLocale];
}

static NSString *const kInitials[19] = {@"ㄱ", @"ㄲ", @"ㄴ", @"ㄷ", @"ㄸ", @"ㄹ", @"ㅁ", @"ㅂ", @"ㅃ", @"ㅅ",
                                        @"ㅆ", @"ㅇ", @"ㅈ", @"ㅉ", @"ㅊ", @"ㅋ", @"ㅌ", @"ㅍ", @"ㅎ"};

static NSInteger initialsIndex(unichar c) {
    for (NSInteger i = 0; i < 19; i++) {
        if ([kInitials[i] characterAtIndex:0] == c) return i;
    }
    return NSNotFound;
}

static BOOL hasSyllable(NSString *text) {
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c >= 0xAC00 && c <= 0xD7A3) return YES;
    }
    return NO;
}

// Each precomposed syllable becomes its initial consonant; the rest is the folded text. Folding normally keeps
// syllables precomposed, but if it decomposed them, the raw text supplies the syllables and the rest is folded
// character by character.
NSString *SGSearchInitials(NSString *text) {
    NSString *folded = fold(text);
    BOOL raw = !hasSyllable(folded) && hasSyllable(text);
    NSString *base = raw ? text : folded;
    NSMutableString *initials = [NSMutableString string];
    for (NSUInteger i = 0; i < base.length; i++) {
        unichar c = [base characterAtIndex:i];
        if (c >= 0xAC00 && c <= 0xD7A3) [initials appendString:kInitials[(c - 0xAC00) / 588]];
        else if (raw) [initials appendString:fold([base substringWithRange:NSMakeRange(i, 1)])];
        else [initials appendFormat:@"%C", c];
    }
    return initials;
}

// A word of only the 19 compatibility consonants a syllable can start with, so it is compared to initials.
BOOL SGSearchIsInitialsWord(NSString *word) {
    if (!word.length) return NO;
    for (NSUInteger i = 0; i < word.length; i++) {
        if (initialsIndex([word characterAtIndex:i]) == NSNotFound) return NO;
    }
    return YES;
}

// A query of initials words, which may be separated by spaces, also compares its start to the title's initials.
static BOOL isInitialsQuery(NSString *query) {
    BOOL any = NO;
    for (NSUInteger i = 0; i < query.length; i++) {
        unichar c = [query characterAtIndex:i];
        if ([[NSCharacterSet whitespaceCharacterSet] characterIsMember:c]) continue;
        if (initialsIndex(c) == NSNotFound) return NO;
        any = YES;
    }
    return any;
}

BOOL SGSearchWordMatches(NSString *word, NSString *folded, NSString *initials) {
    return [(SGSearchIsInitialsWord(word) ? initials : folded) containsString:word];
}

BOOL SGSearchStartsTitle(NSString *query, NSString *foldedTitle, NSString *initialsTitle) {
    if (isInitialsQuery(query) && [initialsTitle hasPrefix:query]) return YES;
    return [foldedTitle hasPrefix:query];
}

static void collect(SGModPage *page, NSArray<NSString *> *trail, UIViewController *(^opener)(void), SGModRow *top,
                    NSUInteger depth, NSMutableArray<SGSettingsHit *> *hits) {
    for (SGModSection *section in page.sections) {
        for (SGModRow *row in section.rows) {
            if (!row.title.length || (row.visible && !row.visible())) continue;
            SGModRow *lead = top ?: row;
            // A row that opens a page is found as that page, whatever kind it is; a choice row's list is not one,
            // and the row itself is what is found. Only a page of rows within reach is built, to read its rows.
            BOOL opens = row.page && !row.choice;
            UIViewController *child = opens && depth < kDepth ? row.page() : nil;
            SGModPage *rows = [child isKindOfClass:SGModPage.class] ? (SGModPage *)child : nil;
            SGSettingsHit *hit = [SGSettingsHit new];
            hit.title = row.title;
            hit.subtitle = row.subtitle;
            hit.trail = trail;
            hit.symbol = lead.symbol;
            hit.tint = lead.tint;
            hit.opens = opens;
            hit.open = opens ? row.page : opener;
            hit.foldedTitle = fold(row.title);
            hit.folded = fold([@[row.title, row.subtitle ?: @"", [trail componentsJoinedByString:@" "]] componentsJoinedByString:@"\n"]);
            // The initials come from the raw text, in case folding decomposes Hangul; computed once per row.
            hit.initialsTitle = SGSearchInitials(row.title);
            hit.initials = SGSearchInitials([@[row.title, row.subtitle ?: @"", [trail componentsJoinedByString:@" "]] componentsJoinedByString:@"\n"]);
            [hits addObject:hit];
            if (rows) collect(rows, [trail arrayByAddingObject:row.title], row.page, lead, depth + 1, hits);
        }
    }
}

@interface SGSettingsResults : SGPage <UISearchResultsUpdating>
@property (nonatomic, weak) SGModPage *owner;
@property (nonatomic, weak) UISearchBar *bar;
@end

// The field's own box sits 8pt inside the bar, so the bar is set out by the table's margin less that: the field
// lines up with the cards under it.
@interface SGSettingsSearchHeader : UIView
@property (nonatomic, weak) UITableView *table;
@property (nonatomic, weak) UISearchBar *bar;
@end

@implementation SGSettingsSearchHeader
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat inset = MAX(0, self.table.layoutMargins.left - 8);
    self.bar.frame = CGRectMake(inset, 0, MAX(0, self.bounds.size.width - 2 * inset), self.bounds.size.height);
}
@end

@implementation SGSettingsResults {
    NSArray<SGSettingsHit *> *_all;
    NSArray<SGSettingsHit *> *_hits;
    UILabel *_none;
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    // The results show over the page from its top, the field still on it: they start under the field, not under
    // the safe area the page's own rows start under.
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _none = [UILabel new];
    _none.text = SGL(@"settings.search.none", @"No Results");
    _none.textColor = SGGrey();
    _none.textAlignment = NSTextAlignmentCenter;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Measured in the results' container, which does not scroll: in the table's own space the field would move
    // with every offset the table is given, and each pass would ask for another.
    UISearchBar *bar = self.bar;
    UIView *container = self.view.superview;
    CGFloat top = bar.window && container ? round(MAX(0, CGRectGetMaxY([container convertRect:bar.bounds fromView:bar]) - CGRectGetMinY(self.view.frame)))
                                          : self.view.safeAreaInsets.top;
    UITableView *table = self.tableView;
    if (fabs(table.contentInset.top - top) > 0.5) {
        UIEdgeInsets inset = table.contentInset;
        inset.top = top;
        table.contentInset = inset;
        table.verticalScrollIndicatorInsets = inset;
        table.contentOffset = CGPointMake(0, -top);
    }
    SGInsetForBars(table);
    _none.font = SGTitleFont();
}

// Every word typed is in the row's title, subtitle or trail; a title starting with what was typed comes first,
// then a title holding every word, then the rest, each in the order of the pages.
- (void)updateSearchResultsForSearchController:(UISearchController *)search {
    NSString *query = [fold(search.searchBar.text) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!query.length) {
        _hits = @[];
        self.tableView.backgroundView = nil;
        [self.tableView reloadData];
        return;
    }
    if (!_all) {
        NSMutableArray<SGSettingsHit *> *all = [NSMutableArray array];
        SGModPage *owner = self.owner;
        if (owner) collect(owner, @[], nil, nil, 0, all);
        _all = all;
    }
    NSArray<NSString *> *words = [query componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSMutableArray<SGSettingsHit *> *ranks[3] = {[NSMutableArray array], [NSMutableArray array], [NSMutableArray array]};
    for (SGSettingsHit *hit in _all) {
        BOOL found = YES, inTitle = YES;
        for (NSString *word in words) {
            if (!word.length) continue;
            if (!SGSearchWordMatches(word, hit.folded, hit.initials)) { found = NO; break; }
            inTitle = inTitle && SGSearchWordMatches(word, hit.foldedTitle, hit.initialsTitle);
        }
        if (!found) continue;
        [ranks[SGSearchStartsTitle(query, hit.foldedTitle, hit.initialsTitle) ? 0 : inTitle ? 1 : 2] addObject:hit];
    }
    NSMutableArray<SGSettingsHit *> *hits = [NSMutableArray array];
    for (int i = 0; i < 3; i++) [hits addObjectsFromArray:ranks[i]];
    _hits = hits.count > kMostHits ? [hits subarrayWithRange:NSMakeRange(0, kMostHits)] : hits;
    self.tableView.backgroundView = _hits.count ? nil : _none;
    [self.tableView reloadData];
    // Each new query reads from its best match down.
    self.tableView.contentOffset = CGPointMake(0, -self.tableView.contentInset.top);
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_hits.count;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return SGSectionGap;
}

// The row as it reads on its page, its trail where its subtitle would be, under the tile of the page it is in.
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    SGSettingsHit *hit = _hits[(NSUInteger)path.row];
    UITableViewCell *cell = SGDequeueCell(table, @"hit");
    NSString *where = hit.trail.count ? [hit.trail componentsJoinedByString:@" › "] : hit.subtitle;
    SGFillCell(cell, hit.title, where, nil, nil);
    UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
    content.image = hit.symbol ? (hit.tint ? SGTileImageTinted(hit.symbol, hit.tint) : SGTileImage(hit.symbol)) : nil;
    cell.contentConfiguration = content;
    cell.separatorInset = UIEdgeInsetsMake(0, hit.symbol ? SGTileRowInset : 16, 0, 0);
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    SGSettingsHit *hit = _hits[(NSUInteger)path.row];
    SGModPage *owner = self.owner;
    UIViewController *page = hit.open ? hit.open() : nil;
    if (!page) {
        // A row of the searched page itself: the results go, and the row is shown where it is.
        UISearchController *search = objc_getAssociatedObject(owner, &kSearchKey);
        search.active = NO;
        [owner revealRowTitled:hit.title];
        return;
    }
    if (!hit.opens && [page isKindOfClass:SGModPage.class]) [(SGModPage *)page revealRowTitled:hit.title];
    [owner.navigationController pushViewController:page animated:YES];
}

@end

void SGSettingsSearchAttach(SGModPage *page) {
    SGSettingsResults *results = [SGSettingsResults new];
    results.owner = page;
    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:results];
    results.bar = search.searchBar;
    search.searchResultsUpdater = results;
    search.hidesNavigationBarDuringPresentation = NO;
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.placeholder = SGL(@"settings.search.placeholder", @"Search");
    search.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    search.searchBar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [search.searchBar sizeToFit];
    // In the table's header rather than the navigation item: the page sits on Spotify's own stack, whose bar
    // is not the system's. The results show over this page only.
    SGSettingsSearchHeader *header = [[SGSettingsSearchHeader alloc] initWithFrame:CGRectMake(0, 0, page.tableView.bounds.size.width, search.searchBar.bounds.size.height)];
    header.table = page.tableView;
    header.bar = search.searchBar;
    [header addSubview:search.searchBar];
    page.tableView.tableHeaderView = header;
    page.definesPresentationContext = YES;
    objc_setAssociatedObject(page, &kSearchKey, search, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
