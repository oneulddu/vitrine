// Play counts In menu on Mac Catalyst: Redesigned/Album/AlbumPlaysMenu.x and AlbumRows.x, each compiled whole
// through Logos, against mocks of Spotify's ⋯ sheet and of an album's track cell. The count is a stub the steps set;
// each step lays the sheet out, posts the counts' change notification as AlbumPlays.m does, or sends a ⋯'s action as
// a tap or VoiceOver would, and checks what the table's header holds. Failures log and exit nonzero
// (harness-fail.h).
#import <UIKit/UIKit.h>
#import "Core/SGUIMode.h"
#import "Settings/SGPageStyle.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Album/Album.h"
#import "../harness-fail.h"

#pragma mark - stubs for what the files call

static NSUInteger sg_count;
NSNotificationName const SGRAlbumPlayCountsDidChangeNotification = @"SGRAlbumPlayCountsDidChange";
BOOL SGRedesignedUI(void) { return YES; }
SGRAlbumPlayCountsPlace SGRAlbumPlayCountsWhere(void) { return SGRAlbumPlayCountsInMenu; }
NSUInteger SGRAlbumPlayCount(NSString *album, NSString *title) {
    return [album isEqualToString:@"Hurry Up Tomorrow"] && [title isEqualToString:@"Cry For Me"] ? sg_count : 0;
}
NSString *SGRAlbumPlaysText(NSUInteger plays) {
    return plays ? [NSString stringWithFormat:@"%lu plays", (unsigned long)plays] : nil;
}
// The Kit's, for AlbumRows.x: the mock marks a page and a track's content by identifier.
static NSString *const kPageID = @"harness.albumPage", *const kTrackID = @"harness.trackContent";
const CGFloat SGRSideMargin = 16;
UIColor *SGRSecondary(void) { return [UIColor colorWithWhite:1 alpha:0.65]; }
UIColor *SGRHairline(void) { return [UIColor colorWithWhite:1 alpha:0.15]; }
BOOL SGRIsTrackContent(UIView *content) { return [content.accessibilityIdentifier isEqualToString:kTrackID]; }
UIView *SGRAlbumPageOf(UIView *view) {
    for (UIView *v = view; v; v = v.superview) if ([v.accessibilityIdentifier isEqualToString:kPageID]) return v;
    return nil;
}
UIView *SGRFindByIdentifier(UIView *root, NSString *identifier, const void *cacheKey) {
    if (!root) return nil;
    BOOL prefix = [identifier hasSuffix:@"*"];
    NSString *stem = prefix ? [identifier substringToIndex:identifier.length - 1] : identifier;
    if (prefix ? [root.accessibilityIdentifier hasPrefix:stem] : [root.accessibilityIdentifier isEqualToString:stem]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = SGRFindByIdentifier(sub, identifier, cacheKey);
        if (found) return found;
    }
    return nil;
}
BOOL SGRCreditRepeatsAlbum(NSString *albumArtist, NSString *rowArtist, NSString *title) { return NO; }
UIFont *SGCategoryCappedFont(UIFontTextStyle style, UIFontWeight weight, UIContentSizeCategory largest) { return [UIFont preferredFontForTextStyle:style]; }
UIFont *SGMonospacedDigitsFont(UIFont *font) { return font; }

#pragma mark - an album's track cell

@interface _TtC12Element_List18CollectionViewCell : UICollectionViewCell @end
@implementation _TtC12Element_List18CollectionViewCell @end

// Spotify's action on a ⋯, which the sheet would follow.
@interface SGUIRefinementsSpotifyAction : NSObject
@property (nonatomic) NSUInteger fired;
- (void)fire;
@end
@implementation SGUIRefinementsSpotifyAction
- (void)fire { self.fired++; }
@end

#pragma mark - Spotify's sheet

@interface _TtC24ContextMenu_InternalImpl25ContextMenuViewController : UIViewController <UITableViewDataSource>
@property (nonatomic, strong) UITableView *table;
@end

@implementation _TtC24ContextMenu_InternalImpl25ContextMenuViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.dataSource = self;
    [self.view addSubview:self.table];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return 3; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = @"Add to queue";
    return cell;
}
@end

#pragma mark - the steps

static NSUInteger sg_checks;

static void expect(BOOL ok, NSString *what) {
    sg_checks++;
    if (!ok) HARNESS_FAIL(@"%@", what);
}

static void layOut(UIViewController *sheet) {
    [sheet.view setNeedsLayout];
    [sheet.view layoutIfNeeded];
}

static void countsChanged(NSUInteger count) {
    sg_count = count;
    [NSNotificationCenter.defaultCenter postNotificationName:SGRAlbumPlayCountsDidChangeNotification object:nil];
}

static UIView *header(_TtC24ContextMenu_InternalImpl25ContextMenuViewController *sheet) {
    return sheet.table.tableHeaderView;
}

static UILabel *labelIn(UIView *view) {
    for (UIView *sub in view.subviews) if ([sub isKindOfClass:UILabel.class]) return (UILabel *)sub;
    return nil;
}

// The line a sheet opened now shows, nil for none: whatever track the last ⋯ action marked.
static NSString *lineOfNewSheet(UIWindow *window) {
    _TtC24ContextMenu_InternalImpl25ContextMenuViewController *sheet = [_TtC24ContextMenu_InternalImpl25ContextMenuViewController new];
    window.rootViewController = sheet;
    layOut(sheet);
    return header(sheet).accessibilityLabel;
}

// AlbumRows.x's ⋯ watch: the track is marked from the ⋯'s action alone (no touch, as VoiceOver activates), and only
// while the ⋯ is still an album track row's; any other control's action leaves a mark as it was.
static void runActionChecks(UIWindow *window) {
    sg_count = 1234;
    UIViewController *host = [UIViewController new];
    UIView *page = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 400, 400)];
    page.accessibilityIdentifier = kPageID;
    [host.view addSubview:page];
    _TtC12Element_List18CollectionViewCell *cell = [[_TtC12Element_List18CollectionViewCell alloc] initWithFrame:CGRectMake(0, 0, 400, 56)];
    [page addSubview:cell];
    UIView *content = [[UIView alloc] initWithFrame:cell.contentView.bounds];
    content.accessibilityIdentifier = kTrackID;
    [cell.contentView addSubview:content];
    UIView *row = [[UIView alloc] initWithFrame:content.bounds];
    row.accessibilityIdentifier = @"Components.UI.RetrievalRowElementUI";
    [content addSubview:row];
    UIView *titleBox = [[UIView alloc] initWithFrame:CGRectMake(16, 8, 300, 18)];
    titleBox.accessibilityIdentifier = @"EncoreConsumerMobile.View.Granular.Title";
    UILabel *title = [[UILabel alloc] initWithFrame:titleBox.bounds];
    title.text = @"Cry For Me";
    [titleBox addSubview:title];
    [row addSubview:titleBox];
    UIControl *more = [[UIControl alloc] initWithFrame:CGRectMake(340, 4, 48, 48)];
    more.accessibilityIdentifier = @"Components.UI.ContextMenuButton-5673WA8EEUSPx1ir26lhGW";
    SGUIRefinementsSpotifyAction *spotify = [SGUIRefinementsSpotifyAction new];
    [more addTarget:spotify action:@selector(fire) forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:more];
    UIControl *other = [[UIControl alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
    [other addTarget:spotify action:@selector(fire) forControlEvents:UIControlEventTouchUpInside];
    [host.view addSubview:other];
    window.rootViewController = host;
    SGRAlbumSetTitle(page, @"Hurry Up Tomorrow");
    void (^layOutCell)(void) = ^{
        [cell setNeedsLayout];
        [cell layoutIfNeeded];
    };
    layOutCell();

    // The album row's ⋯: its action marks the track for the sheet it opens.
    [more sendActionsForControlEvents:UIControlEventTouchUpInside];
    expect(spotify.fired == 1, @"Spotify's own action still runs");
    expect([lineOfNewSheet(window) isEqualToString:@"1234 plays"], @"the album row's ⋯ marks its track from its action");

    // The cell is reused for a row of no album, its title another: its old ⋯ marks nothing, before and after the
    // reused cell's layout, and the mark there was stays.
    window.rootViewController = host;
    [cell prepareForReuse];
    content.accessibilityIdentifier = nil;
    title.text = @"Other";
    SGRAlbumPlaysMarkMenu(@"Hurry Up Tomorrow", @"Cry For Me");
    [more sendActionsForControlEvents:UIControlEventTouchUpInside];
    layOutCell();
    [more sendActionsForControlEvents:UIControlEventTouchUpInside];
    expect([lineOfNewSheet(window) isEqualToString:@"1234 plays"], @"a ⋯ reused out of an album leaves the mark alone");

    // An album's track row again, then moved off the album page with no pass of its own since: the action checks
    // the row again rather than trusting its flag.
    window.rootViewController = host;
    content.accessibilityIdentifier = kTrackID;
    title.text = @"Cry For Me";
    layOutCell();
    [host.view addSubview:cell];
    title.text = @"Other";
    SGRAlbumPlaysMarkMenu(@"Hurry Up Tomorrow", @"Cry For Me");
    [more sendActionsForControlEvents:UIControlEventTouchUpInside];
    expect([lineOfNewSheet(window) isEqualToString:@"1234 plays"], @"a ⋯ no longer on an album page leaves the mark alone");

    // Any other control's action leaves the mark as it was.
    window.rootViewController = host;
    SGRAlbumPlaysMarkMenu(@"Hurry Up Tomorrow", @"Cry For Me");
    [other sendActionsForControlEvents:UIControlEventTouchUpInside];
    expect([lineOfNewSheet(window) isEqualToString:@"1234 plays"], @"an unflagged control leaves the mark alone");
}

static void run(UIWindow *window) {
    // A sheet with no ⋯ action before it gets no line, whatever the count.
    sg_count = 7;
    _TtC24ContextMenu_InternalImpl25ContextMenuViewController *unmarked = [_TtC24ContextMenu_InternalImpl25ContextMenuViewController new];
    window.rootViewController = unmarked;
    layOut(unmarked);
    expect(header(unmarked) == nil, @"a sheet not opened from a row's ⋯ has no line");

    // The row's ⋯ sent its action; the log has not been read when the sheet first lays out.
    sg_count = 0;
    SGRAlbumPlaysMarkMenu(@"Hurry Up Tomorrow", @"Cry For Me");
    _TtC24ContextMenu_InternalImpl25ContextMenuViewController *sheet = [_TtC24ContextMenu_InternalImpl25ContextMenuViewController new];
    window.rootViewController = sheet;
    layOut(sheet);
    expect(header(sheet) == nil, @"no count yet, no line");

    // The counts arrive after the sheet's last pass: the notification alone brings the line.
    countsChanged(1234);
    UIView *line = header(sheet);
    expect([line.accessibilityLabel isEqualToString:@"1234 plays"], [NSString stringWithFormat:@"the line comes with the counts, got %@ %@", line.class, line.accessibilityLabel]);
    expect(!line.userInteractionEnabled && (line.accessibilityTraits & UIAccessibilityTraitStaticText) && !(line.accessibilityTraits & UIAccessibilityTraitButton),
           @"the line is static text, not a button");
    expect([labelIn(line).textColor isEqual:UIColor.secondaryLabelColor], @"the line's text is the secondary label color");

    // The line is as tall as its text. (Catalyst keeps one footnote size whatever the text size, so the growth at
    // accessibility sizes is looked at in the simulator's album harness instead.)
    [line layoutIfNeeded];
    UILabel *text = labelIn(line);
    CGFloat needed = ceil([text sizeThatFits:CGSizeMake(text.bounds.size.width, CGFLOAT_MAX)].height);
    expect(text.bounds.size.height >= needed, [NSString stringWithFormat:@"the text is whole: %.1f of %.1f", text.bounds.size.height, needed]);

    // The count goes (the log erased): so does the line, and it comes back with a count.
    countsChanged(0);
    expect(header(sheet) == nil, @"the line goes with the count");
    countsChanged(5);
    expect([header(sheet).accessibilityLabel isEqualToString:@"5 plays"], @"the line comes back with a count");

    // Spotify puts a view of its own in the header: the line gives way, on the next pass and on the next change.
    UIView *spotify = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 40)];
    sheet.table.tableHeaderView = spotify;
    layOut(sheet);
    expect(header(sheet) == spotify, @"a pass leaves Spotify's header in place");
    countsChanged(6);
    expect(header(sheet) == spotify, @"a change leaves Spotify's header in place");

    runActionChecks(window);

    printf("ui-refinements menu: %lu checks passed\n", (unsigned long)sg_checks);
    fflush(stdout);
    exit(0);
}

@interface SGUIRefinementsMenuScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGUIRefinementsMenuScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{ run(self.window); });
}
@end

@interface SGUIRefinementsMenuApp : UIResponder <UIApplicationDelegate>
@end
@implementation SGUIRefinementsMenuApp
@end

int main(int argc, char *argv[]) {
    // A run that never reaches its end fails rather than hangs.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ HARNESS_FAIL(@"timed out"); });
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGUIRefinementsMenuApp.class));
    }
}
