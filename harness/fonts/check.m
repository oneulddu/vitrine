// The free fonts page and FontLibrary.m's registration: opening the page registers no font on the main
// thread; every installed family is registered on the library's queue, then published and announced on main.
// Core Text is replaced at the two calls FontLibrary.m makes (the descriptors of a file, its registration)
// so a fixture file of the catalog's size stands for a font; the family it answers is Helvetica.
#import <CoreText/CoreText.h>
#import <UIKit/UIKit.h>
#import <stdatomic.h>
#import "../harness-fail.h"

static atomic_int sg_mainCalls, sg_workerCalls;
static CFArrayRef harnessDescriptors(CFURLRef url) {
    atomic_fetch_add(NSThread.isMainThread ? &sg_mainCalls : &sg_workerCalls, 1);
    CTFontDescriptorRef face = CTFontDescriptorCreateWithNameAndSize(CFSTR("Helvetica"), 12);
    CFArrayRef faces = CFArrayCreate(NULL, (const void **)&face, 1, &kCFTypeArrayCallBacks);
    CFRelease(face);
    return faces;
}
static bool harnessRegister(CFURLRef url, CTFontManagerScope scope, CFErrorRef *error) {
    atomic_fetch_add(NSThread.isMainThread ? &sg_mainCalls : &sg_workerCalls, 1);
    return true;
}
static bool harnessUnregister(CFURLRef url, CTFontManagerScope scope, CFErrorRef *error) {
    return true;
}
#define CTFontManagerCreateFontDescriptorsFromURL harnessDescriptors
#define CTFontManagerRegisterFontsForURL harnessRegister
#define CTFontManagerUnregisterFontsForURL harnessUnregister
#import "Shared/Fonts/FontLibrary.m"

SGAppFont SGAppFontChosen(void) { return SGAppFontSpotify; }
NSArray<NSString *> *SGAppFontNames(void) { return @[]; }
NSArray<NSString *> *SGAppFontFamilies(void) { return @[]; }

static void pumpUntil(BOOL (^done)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!done() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    HARNESS_CHECK(done());
}

// A file of exactly the catalog's size, which is all SGFontLibraryInstalled asks of it.
static void install(NSString *identifier) {
    NSFileManager *files = NSFileManager.defaultManager;
    for (size_t i = 0; i < sizeof kFamilies / sizeof *kFamilies; i++) {
        if (![kFamilies[i].identifier isEqualToString:identifier]) continue;
        HARNESS_CHECK([files createDirectoryAtURL:familyFolder(identifier) withIntermediateDirectories:YES attributes:nil error:nil]);
        for (const SGFontFileLine *file = kFamilies[i].files; file < kFamilies[i].files + 5 && file->name; file++) {
            NSString *path = [familyFolder(identifier) URLByAppendingPathComponent:file->name].path;
            HARNESS_CHECK([files createFileAtPath:path contents:nil attributes:nil]);
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
            HARNESS_CHECK([handle truncateAtOffset:(unsigned long long)file->size error:nil]);
            [handle closeFile];
        }
        return;
    }
    HARNESS_FAIL(@"%@ is not in the catalog", identifier);
}

static NSString *rowFamily(UITableViewController *page, NSString *identifier) {
    SGLibraryFont *font = SGFontLibraryFont(identifier);
    NSUInteger row = [[SGFontLibrary() filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"korean == %@", @(font.korean)]] indexOfObject:font];
    NSIndexPath *path = [NSIndexPath indexPathForRow:(NSInteger)row inSection:font.korean ? 0 : 1];
    UITableViewCell *cell = [page tableView:page.tableView cellForRowAtIndexPath:path];
    return ((UIListContentConfiguration *)cell.contentConfiguration).textProperties.font.familyName;
}

int main(void) { @autoreleasepool {
    [NSFileManager.defaultManager removeItemAtURL:libraryFolder() error:nil];
    install(@"nanumgothic");
    install(@"lato");

    __block NSMutableArray<NSString *> *announced = [NSMutableArray array];
    id token = [NSNotificationCenter.defaultCenter addObserverForName:SGFontLibraryChangedNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            HARNESS_CHECK(NSThread.isMainThread);
            [announced addObject:note.userInfo[@"identifier"]];
        }];

    // Opening the page registers nothing on main, and nothing is published until main runs again.
    UITableViewController *page = (UITableViewController *)SGFontLibraryPage();
    [page loadViewIfNeeded];
    HARNESS_CHECK(atomic_load(&sg_mainCalls) == 0);
    HARNESS_CHECK(!SGFontLibraryRegisteredFamily(@"lato") && !SGFontLibraryRegisteredFamily(@"nanumgothic"));
    HARNESS_CHECK(![rowFamily(page, @"lato") isEqual:@"Helvetica"]);

    pumpUntil(^BOOL { return announced.count == 2; });
    HARNESS_CHECK([SGFontLibraryRegisteredFamily(@"lato") isEqual:@"Helvetica"]);
    HARNESS_CHECK([SGFontLibraryRegisteredFamily(@"nanumgothic") isEqual:@"Helvetica"]);
    HARNESS_CHECK([announced containsObject:@"lato"] && [announced containsObject:@"nanumgothic"]);
    HARNESS_CHECK([rowFamily(page, @"lato") isEqual:@"Helvetica"]);
    // Two families of two and three files: each file registered once, each family described once, none on main.
    HARNESS_CHECK(atomic_load(&sg_workerCalls) == 7 && atomic_load(&sg_mainCalls) == 0);

    // Opening it again registers nothing twice and announces nothing new.
    SGFontLibraryRegisterInstalled();
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    HARNESS_CHECK(announced.count == 2 && atomic_load(&sg_workerCalls) == 7);

    // A removal behind a pending registration wins: the family is never published after it.
    [announced removeAllObjects];
    install(@"poppins");
    install(@"jua");
    SGFontLibraryRegisterInstalled();
    SGFontLibraryRemove(@"poppins");
    HARNESS_CHECK(!SGFontLibraryInstalled(@"poppins") && !SGFontLibraryRegisteredFamily(@"poppins"));
    pumpUntil(^BOOL { return [announced containsObject:@"jua"]; });
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    HARNESS_CHECK(!SGFontLibraryRegisteredFamily(@"poppins"));

    // The synchronous entry still answers a family nothing has registered yet, and publishes it.
    install(@"barlow");
    HARNESS_CHECK(!SGFontLibraryRegisteredFamily(@"barlow"));
    HARNESS_CHECK([SGFontLibraryRegister(@"barlow") isEqual:@"Helvetica"]);
    HARNESS_CHECK([SGFontLibraryRegisteredFamily(@"barlow") isEqual:@"Helvetica"]);

    [NSNotificationCenter.defaultCenter removeObserver:token];
    for (NSString *identifier in @[@"nanumgothic", @"lato", @"jua", @"barlow"]) SGFontLibraryRemove(identifier);
    [NSFileManager.defaultManager removeItemAtURL:libraryFolder() error:nil];
    puts("PASS: free fonts register off main on a serial queue, publish and refresh rows on main, and a removal beats a pending registration");
    return 0;
} }
