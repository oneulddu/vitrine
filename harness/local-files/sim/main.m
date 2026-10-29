// Edit info in the simulator: EditInfoMenu.x and LocalFiles.m as the tweak compiles them, on a mock of
// Spotify's context menu sheet presented over a player that plays a local file. The script taps the row,
// which closes the menu and brings up the editor, then types, picks a cover, saves, opens it again,
// restores the file's info, and tries to swipe away unsaved changes. It logs PASS or FAIL for each step
// and `[harness] SHOT <name>` when the screen is worth a screenshot (build-sim.sh takes them).
#import <UIKit/UIKit.h>
#import "Shared/LocalFiles/LocalFiles.h"
#import "Shared/LocalFiles/LocalInfoLookup.h"
#import <objc/runtime.h>

static NSString *const kURI = @"spotify:local:Daft+Punk:Discovery:One+More+Time:320";
static int sg_failures;
static NSUInteger sg_searches, sg_covers;
static BOOL sg_holdSearch, sg_conflictingPresentation;
static BOOL sg_filesBoundaryChecked, sg_photosBoundaryChecked;

#define CHECK(what, cond) do { BOOL ok = (cond); if (!ok) sg_failures++; NSLog(@"[harness] %@ %@", ok ? @"PASS" : @"FAIL", what); } while (0)

// What EditInfoMenu.x reads of the player: the track playing, and that the menu is the player's.
@interface SGHarnessTrack : NSObject
@property (nonatomic, strong) id URI;
@end
@implementation SGHarnessTrack
@end
@interface SGHarnessState : NSObject
@property (nonatomic, strong) SGHarnessTrack *track;
@end
@implementation SGHarnessState
@end

id SGPlayerState(void) {
    SGHarnessState *state = [SGHarnessState new];
    state.track = [SGHarnessTrack new];
    state.track.URI = [NSURL URLWithString:kURI];
    return state;
}
NSString *SGURIString(id uri) {
    return [uri isKindOfClass:NSURL.class] ? [(NSURL *)uri absoluteString] : uri;
}
BOOL SGPlayerMenuIsPlayers(UIViewController *menu) {
    return YES;
}

// Spotify's context menu sheet, as far as the hook goes: a table whose layout runs the hook.
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
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = @[@"Add to playlist", @"Go to queue", @"Share"][(NSUInteger)indexPath.row];
    return cell;
}
@end

static void after(double seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

static void shot(NSString *name) {
    NSLog(@"[harness] SHOT %@", name);
}

static UIImage *redSquare(void) {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(300, 300)] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.systemRedColor setFill];
        UIRectFill(CGRectMake(0, 0, 300, 300));
    }];
}

// All requests, including accidental ones, terminate here. The harness never reaches the network.
@interface SGInfoFixtureProtocol : NSURLProtocol
@property(atomic) BOOL stopped;
- (void)finishLoading;
@end
static SGInfoFixtureProtocol *sg_pendingSearch;
@implementation SGInfoFixtureProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    if ([self.request.URL.host isEqual:@"itunes.apple.com"]) {
        ++sg_searches;
        if (sg_holdSearch) { sg_pendingSearch = self; return; }
    } else ++sg_covers;
    [self finishLoading];
}
- (void)finishLoading {
    if (self.stopped) return;
    NSData *data;
    if ([self.request.URL.host isEqual:@"itunes.apple.com"]) {
        data = [NSJSONSerialization dataWithJSONObject:@{@"results": @[
            @{@"trackName": @"One More Time", @"artistName": @"Daft Punk", @"collectionName": @"Discovery (Remastered)",
              @"trackTimeMillis": @320000, @"releaseDate": @"2001-03-12T00:00:00Z", @"artworkUrl100": @"https://is1-ssl.mzstatic.com/100x100bb.png"},
            @{@"trackName": @"One More Time (Radio Edit)", @"artistName": @"Daft Punk", @"collectionName": @"Discovery",
              @"trackTimeMillis": @319000, @"releaseDate": @"2001-03-12T00:00:00Z", @"artworkUrl100": @"https://is1-ssl.mzstatic.com/100x100bb.png"}
        ]} options:0 error:nil];
    } else {
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = 1;
        UIImage *large = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1600, 1600) format:format]
            imageWithActions:^(UIGraphicsImageRendererContext *context) {
                [UIColor.systemRedColor setFill];
                UIRectFill(CGRectMake(0, 0, 1600, 1600));
            }];
        data = UIImagePNGRepresentation(large);
    }
    [self.client URLProtocol:self didReceiveResponse:[[NSHTTPURLResponse alloc] initWithURL:self.request.URL
        statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{}] cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading { self.stopped = YES; }
@end

static void installInfoFixture(void) {
    Method method = class_getClassMethod(NSURLSessionConfiguration.class, @selector(ephemeralSessionConfiguration));
    IMP original = method_getImplementation(method);
    method_setImplementation(method, imp_implementationWithBlock(^id(id cls) {
        NSURLSessionConfiguration *config = ((id (*)(id, SEL))original)(cls, @selector(ephemeralSessionConfiguration));
        config.protocolClasses = @[SGInfoFixtureProtocol.class];
        return config;
    }));
    Method presentation = class_getInstanceMethod(UIViewController.class, @selector(presentViewController:animated:completion:));
    IMP present = method_getImplementation(presentation);
    method_setImplementation(presentation, imp_implementationWithBlock(^(UIViewController *owner, UIViewController *next, BOOL animated, void (^completion)(void)) {
        // The OS-owned Files/Photos services may dismiss themselves on an empty simulator.
        // Keep their presentation boundary, but supply an in-process sheet so dismissing it
        // cannot accidentally dismiss the editor. Production still constructs each real picker.
        if ([next isKindOfClass:UIDocumentPickerViewController.class] || [next isKindOfClass:UIImagePickerController.class]) {
            BOOL cancelled = ![(SGLocalInfoLookup *)[owner valueForKey:@"infoLookup"] busy] &&
                ((UIBarButtonItem *)owner.toolbarItems[1]).enabled;
            if ([next isKindOfClass:UIDocumentPickerViewController.class]) {
                sg_filesBoundaryChecked = YES;
                CHECK(@"Files picker cancels lookup and re-enables Find Info", cancelled);
            } else {
                sg_photosBoundaryChecked = YES;
                CHECK(@"Photos picker cancels lookup and re-enables Find Info", cancelled);
            }
            next = [UIViewController new];
            next.view.backgroundColor = UIColor.systemBackgroundColor;
        }
        if (owner.presentedViewController && [next isKindOfClass:UINavigationController.class] &&
            [NSStringFromClass(((UINavigationController *)next).topViewController.class) isEqual:@"SGLocalInfoReview"])
            sg_conflictingPresentation = YES;
        ((void (*)(id, SEL, id, BOOL, id))present)(owner, @selector(presentViewController:animated:completion:), next, animated, completion);
    }));
}

@interface UIViewController (InfoHarnessActions)
- (void)pickCoverFromFiles:(BOOL)files;
@end

@interface SGHarnessApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation SGHarnessApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyLocalFileEdits];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *player = [UIViewController new];
    player.view.backgroundColor = UIColor.blackColor;
    self.window.rootViewController = player;
    [self.window makeKeyAndVisible];
    [self runOn:player];
    return YES;
}

- (UIViewController *)editorOver:(UIViewController *)player {
    UINavigationController *navigation = (UINavigationController *)player.presentedViewController;
    if (![navigation isKindOfClass:UINavigationController.class]) return nil;
    UIViewController *editor = navigation.viewControllers.firstObject;
    return [NSStringFromClass(editor.class) isEqualToString:@"SGLocalFileEditor"] ? editor : nil;
}

- (void)runOn:(UIViewController *)player {
    if ([NSProcessInfo.processInfo.arguments containsObject:@"suggest"]) {
        installInfoFixture();
        [self runSuggestOn:player];
        return;
    }
    BOOL large = [NSProcessInfo.processInfo.arguments containsObject:@"large"];
    __block UIViewController *menu;
    after(1, ^{
        menu = [_TtC24ContextMenu_InternalImpl25ContextMenuViewController new];
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:menu];
        navigation.navigationBarHidden = YES;
        navigation.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent];
        [player presentViewController:navigation animated:YES completion:nil];
    });
    after(2.5, ^{
        UIView *footer = ((_TtC24ContextMenu_InternalImpl25ContextMenuViewController *)menu).table.tableFooterView;
        CHECK(@"the menu has the Edit info row", [NSStringFromClass(footer.class) isEqualToString:@"SGEditInfoRow"]);
        UILabel *title = nil;
        for (UIView *view in footer.subviews) if ([view isKindOfClass:UILabel.class]) title = (UILabel *)view;
        UITraitCollection *traits = [UITraitCollection traitCollectionWithPreferredContentSizeCategory:
            large ? UIContentSizeCategoryExtraLarge : UIContentSizeCategoryLarge];
        UIFont *regular = [UIFont systemFontOfSize:
            [UIFont preferredFontForTextStyle:UIFontTextStyleBody compatibleWithTraitCollection:traits].pointSize];
        NSNumber *weight = [title.font.fontDescriptor objectForKey:UIFontDescriptorTraitsAttribute][UIFontWeightTrait];
        NSNumber *regularWeight = [regular.fontDescriptor objectForKey:UIFontDescriptorTraitsAttribute][UIFontWeightTrait];
        CHECK(@"Edit info uses regular Body text capped at Extra Large",
              title.font.pointSize == regular.pointSize && [weight isEqualToNumber:regularWeight]);
        shot(@"menu");
        [(UIControl *)footer sendActionsForControlEvents:UIControlEventTouchUpInside];
    });
    after(4.5, ^{
        UIViewController *editor = [self editorOver:player];
        CHECK(@"the menu closed and the editor came up over the player", editor != nil);
        CHECK(@"the editor is dark", editor.navigationController.overrideUserInterfaceStyle == UIUserInterfaceStyleDark);
        NSArray<UITextField *> *fields = [editor valueForKey:@"fields"];
        CHECK(@"the fields show the file's names", [fields[0].text isEqualToString:@"One More Time"] && [fields[1].text isEqualToString:@"Daft Punk"]);
        CHECK(@"Save is off with nothing changed", !editor.navigationItem.rightBarButtonItem.enabled && !editor.modalInPresentation);
        shot(large ? @"editor-large" : @"editor");
        if (large) after(2, ^{ exit(sg_failures ? 1 : 0); });
    });
    if (large) return;
    after(6, ^{
        UIViewController *editor = [self editorOver:player];
        NSArray<UITextField *> *fields = [editor valueForKey:@"fields"];
        fields[0].text = @"One More Time (Edit)";
        [fields[0] sendActionsForControlEvents:UIControlEventEditingChanged];
        CHECK(@"a typed name turns Save on and holds a swipe", editor.navigationItem.rightBarButtonItem.enabled && editor.modalInPresentation);
        [editor performSelector:@selector(useCover:) withObject:redSquare()];
        CHECK(@"a picked cover is not stored before Save", !SGLocalFileEditFor(kURI));
    });
    after(7, ^{ shot(@"edited"); });
    after(8, ^{
        UIViewController *editor = [self editorOver:player];
        UIBarButtonItem *save = editor.navigationItem.rightBarButtonItem;
        [[UIApplication sharedApplication] sendAction:save.action to:save.target from:save forEvent:nil];
        NSDictionary *edit = SGLocalFileEditFor(kURI);
        CHECK(@"Save stores the name and the cover", [edit[@"title"] isEqualToString:@"One More Time (Edit)"] && SGLocalFileCoverPath(edit));
        CHECK(@"the rename gives a new lyrics key", [SGLocalFileLyricsKey(kURI) containsString:@"#"]);
    });
    after(9.5, ^{ SGLocalFilePresentEditor(player, kURI); });
    after(11, ^{
        UIViewController *editor = [self editorOver:player];
        NSArray<UITextField *> *fields = [editor valueForKey:@"fields"];
        UITableViewCell *restore = [editor valueForKey:@"restoreCell"];
        CHECK(@"opened again, it shows the edit and offers the restore", [fields[0].text isEqualToString:@"One More Time (Edit)"] && restore.userInteractionEnabled);
        shot(@"reopened");
    });
    after(12.5, ^{
        UIViewController *editor = [self editorOver:player];
        NSArray<UITextField *> *fields = [editor valueForKey:@"fields"];
        UITableViewCell *restore = [editor valueForKey:@"restoreCell"];
        [(UITableViewController *)editor tableView:[(UITableViewController *)editor tableView] didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2]];
        CHECK(@"Restore puts the file's names back, unsaved", [fields[0].text isEqualToString:@"One More Time"] && SGLocalFileEditFor(kURI)
              && editor.navigationItem.rightBarButtonItem.enabled && !restore.userInteractionEnabled);
        UIBarButtonItem *save = editor.navigationItem.rightBarButtonItem;
        [[UIApplication sharedApplication] sendAction:save.action to:save.target from:save forEvent:nil];
        CHECK(@"saved, the edit and its cover are gone", !SGLocalFileEditFor(kURI) && [SGLocalFileLyricsKey(kURI) isEqualToString:kURI]);
    });
    after(14, ^{ SGLocalFilePresentEditor(player, kURI); });
    after(15.5, ^{
        UIViewController *editor = [self editorOver:player];
        NSArray<UITextField *> *fields = [editor valueForKey:@"fields"];
        UITableViewCell *restore = [editor valueForKey:@"restoreCell"];
        CHECK(@"with no edit, Restore is off", !restore.userInteractionEnabled);
        fields[2].text = @"Homework";
        [fields[2] sendActionsForControlEvents:UIControlEventEditingChanged];
        [(id<UIAdaptivePresentationControllerDelegate>)editor presentationControllerDidAttemptToDismiss:editor.navigationController.presentationController];
    });
    after(17, ^{
        UIViewController *editor = [self editorOver:player];
        UIAlertController *confirm = (UIAlertController *)editor.presentedViewController;
        CHECK(@"a swipe away with changes asks first", [confirm isKindOfClass:UIAlertController.class] && confirm.preferredStyle == UIAlertControllerStyleActionSheet
              && [confirm.actions.firstObject.title isEqualToString:@"Discard changes"]);
        shot(@"discard");
    });
    after(19, ^{
        NSLog(@"[harness] %@: %d failed", sg_failures ? @"FAIL" : @"PASS", sg_failures);
        exit(sg_failures ? 1 : 0);
    });
}

- (UITableViewController *)reviewOver:(UIViewController *)editor {
    UINavigationController *nav = (id)editor.presentedViewController;
    if (![nav isKindOfClass:UINavigationController.class]) return nil;
    return (id)nav.viewControllers.firstObject;
}

- (void)runSuggestOn:(UIViewController *)player {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyLocalFileSuggest];
    after(1, ^{ SGLocalFilePresentEditor(player, kURI); });
    after(1.8, ^{
        [self editorOver:player].navigationController.sheetPresentationController.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;
    });
    after(2.5, ^{
        UIViewController *editor = [self editorOver:player];
        CHECK(@"Find Info is default on and makes no automatic request", editor.toolbarItems.count == 3 && sg_searches == 0);
        shot(@"find-info");
        after(0.5, ^{
            [editor performSelector:@selector(findInfo)];
            [editor performSelector:@selector(findInfo)];
        });
    });
    after(4, ^{
        UIViewController *editor = [self editorOver:player];
        UITableViewController *review = [self reviewOver:editor];
        CHECK(@"one search and review, no eager cover download", review && sg_searches == 1 && sg_covers == 0);
        if (!review) { NSLog(@"[harness] FAIL missing review"); exit(1); }
        NSIndexPath *album = [NSIndexPath indexPathForRow:2 inSection:0];
        NSIndexPath *title = [NSIndexPath indexPathForRow:0 inSection:0];
        CHECK(@"only differing fields checked", [review tableView:review.tableView cellForRowAtIndexPath:album].accessoryType == UITableViewCellAccessoryCheckmark &&
            [review tableView:review.tableView cellForRowAtIndexPath:title].accessoryType == UITableViewCellAccessoryNone);
        shot(@"review-best");
        after(0.8, ^{
            [review tableView:review.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]];
            [review tableView:review.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
            CHECK(@"Other Matches preserves unchecked Cover", [review tableView:review.tableView cellForRowAtIndexPath:
                [NSIndexPath indexPathForRow:3 inSection:0]].accessoryType == UITableViewCellAccessoryNone);
        });
    });
    after(5.5, ^{
        UIViewController *editor = [self editorOver:player];
        UITableViewController *review = [self reviewOver:editor];
        shot(@"review-other");
        after(0.5, ^{ [review performSelector:@selector(reject)]; });
        CHECK(@"Not This Song never saves", !SGLocalFileEditFor(kURI));
    });
    after(7, ^{
        UIViewController *editor = [self editorOver:player];
        CHECK(@"reject leaves editor unchanged", !editor.navigationItem.rightBarButtonItem.enabled);
        [editor performSelector:@selector(findInfo)];
    });
    after(8.5, ^{
        UIViewController *editor = [self editorOver:player];
        UITableViewController *review = [self reviewOver:editor];
        [review tableView:review.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]];
        [review performSelector:@selector(use)];
    });
    after(10, ^{
        UIViewController *editor = [self editorOver:player];
        NSArray<UITextField *> *fields = [editor valueForKey:@"fields"];
        CHECK(@"Use only fills selected fields; no overlay write", [fields[0].text isEqual:@"One More Time"] &&
            [fields[2].text isEqual:@"Discovery (Remastered)"] && !SGLocalFileEditFor(kURI) && sg_covers == 0);
        CHECK(@"accepted values retain dirty/discard guard", editor.modalInPresentation && editor.navigationItem.rightBarButtonItem.enabled);
        shot(@"accepted-unsaved");
        after(0.5, ^{
            [editor performSelector:@selector(save)];
            CHECK(@"existing Save publishes the URI-keyed overlay", [SGLocalFileEditFor(kURI)[@"album"] isEqual:@"Discovery (Remastered)"]);
        });
    });
    after(11.5, ^{ SGLocalFilePresentEditor(player, kURI); });
    after(13, ^{
        [self editorOver:player].navigationController.sheetPresentationController.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;
        [[self editorOver:player] performSelector:@selector(findInfo)];
    });
    after(14.5, ^{ [[self reviewOver:[self editorOver:player]] performSelector:@selector(use)]; });
    after(16, ^{
        UIViewController *editor = [self editorOver:player];
        UIImage *cover = [editor valueForKey:@"cover"];
        CHECK(@"Use downloads cover only on demand, fills picked cover without saving", sg_covers == 1 && cover &&
            MAX(cover.size.width, cover.size.height) == 1200 && !SGLocalFileEditFor(kURI)[@"cover"]);
        shot(@"accepted-cover");
        after(0.5, ^{
            [editor performSelector:@selector(save)];
            CHECK(@"Save sends picked cover through existing cover store", SGLocalFileEditFor(kURI)[@"cover"] != nil);
        });
    });
    after(17.5, ^{
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:SGKeyLocalFileSuggest];
        SGLocalFilePresentEditor(player, kURI);
    });
    after(19, ^{
        UIViewController *editor = [self editorOver:player];
        CHECK(@"off hides Find Info", editor.toolbarItems.count == 0);
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyLocalFileSuggest];
        SGLocalFileSaveEdit(kURI, @{}, nil, NO);
        [editor dismissViewControllerAnimated:YES completion:nil];
    });
    after(20, ^{ SGLocalFilePresentEditor(player, kURI); });
    after(21, ^{
        UIViewController *editor = [self editorOver:player];
        ((UITextField *)[editor valueForKey:@"fields"][0]).text = @"Pending Files";
        sg_holdSearch = YES;
        [editor performSelector:@selector(findInfo)];
    });
    after(21.6, ^{ [[self editorOver:player] pickCoverFromFiles:YES]; });
    after(22.5, ^{
        UIViewController *editor = [self editorOver:player];
        [editor dismissViewControllerAnimated:YES completion:nil];
    });
    after(23.5, ^{
        UIViewController *editor = [self editorOver:player];
        ((UITextField *)[editor valueForKey:@"fields"][0]).text = @"Pending Photos";
        [editor performSelector:@selector(findInfo)];
    });
    after(24.1, ^{ [[self editorOver:player] pickCoverFromFiles:NO]; });
    after(25, ^{
        UIViewController *editor = [self editorOver:player];
        [editor dismissViewControllerAnimated:YES completion:nil];
    });
    after(26, ^{
        UIViewController *editor = [self editorOver:player];
        ((UITextField *)[editor valueForKey:@"fields"][0]).text = @"Blocked Review";
        [editor performSelector:@selector(findInfo)];
        [editor performSelector:@selector(cancel)]; // dirty editor presents its real discard/keep-editing guard
    });
    after(27, ^{
        CHECK(@"pending lookup reaches discard confirmation race", sg_pendingSearch && !sg_pendingSearch.stopped);
        [sg_pendingSearch finishLoading];
    });
    after(28, ^{
        UIViewController *editor = [self editorOver:player];
        CHECK(@"both picker presentation boundaries were exercised", sg_filesBoundaryChecked && sg_photosBoundaryChecked);
        CHECK(@"answer behind another controller is dropped and button reset", !sg_conflictingPresentation &&
            ((UIBarButtonItem *)editor.toolbarItems[1]).enabled && [editor.presentedViewController isKindOfClass:UIAlertController.class]);
        sg_holdSearch = NO;
        sg_pendingSearch = nil;
        NSLog(@"[harness] %@: %d failed", sg_failures ? @"FAIL" : @"PASS", sg_failures);
        exit(sg_failures ? 1 : 0);
    });
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGHarnessApp.class));
    }
}
