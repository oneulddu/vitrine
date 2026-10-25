// The actual picker/import and font-page selection, with a controlled pause at the worker copy.
#import <CoreText/CoreText.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Shared/Fonts/Fonts.h"
#import "../harness-fail.h"

static NSURL *fixture;
static IMP originalCopy, blockedCopy;
static Method copyMethod;
typedef NS_ENUM(NSUInteger, FontCheck) {
    PickNewYork, RemovePreference, RestorePreference, SwitchFamily, SwitchLibrary,
    KeepPreference, KeepUnsetPreference, RestartUnsetPreference, FontCheckCount
};
static FontCheck scenario;
static UITableViewController *page;

static void runImport(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    for (NSString *key in @[SGKeyAppFont, SGKeyAppFontFamily, SGKeyAppFontLibrary]) [store removeObjectForKey:key];
    if (scenario != KeepUnsetPreference && scenario != RestartUnsetPreference) SGSetInt(SGKeyAppFont, SGAppFontSpotify);
    if (scenario == SwitchFamily) {
        SGSetInt(SGKeyAppFont, SGAppFontFamily);
        [store setObject:@"Avenir Next" forKey:SGKeyAppFontFamily];
    } else if (scenario == SwitchLibrary) {
        SGSetInt(SGKeyAppFont, SGAppFontLibrary);
        [store setObject:@"fixture-library-a" forKey:SGKeyAppFontLibrary];
    }
    page = [NSClassFromString(@"SGFontPage") new];
    id<UIDocumentPickerDelegate> picker = [NSClassFromString(@"SGFontPicker") new];
    [(id)picker setValue:[^{
        HARNESS_CHECK(NSThread.isMainThread);
        switch (scenario) {
            case PickNewYork: HARNESS_CHECK(SGAppFontChosen() == SGAppFontSerif); break;
            case RemovePreference: HARNESS_CHECK([store objectForKey:SGKeyAppFont] == nil); break;
            case RestorePreference: HARNESS_CHECK(SGAppFontChosen() == SGAppFontRounded); break;
            case SwitchFamily:
                HARNESS_CHECK(SGAppFontChosen() == SGAppFontFamily);
                HARNESS_CHECK([[store objectForKey:SGKeyAppFontFamily] isEqual:@"Georgia"]);
                break;
            case SwitchLibrary:
                HARNESS_CHECK([[store objectForKey:SGKeyAppFont] isEqual:@(SGAppFontLibrary)]);
                HARNESS_CHECK([[store objectForKey:SGKeyAppFontLibrary] isEqual:@"fixture-library-b"]);
                break;
            case KeepPreference:
            case KeepUnsetPreference: HARNESS_CHECK(SGAppFontChosen() == SGAppFontCustom); break;
            case RestartUnsetPreference:
                HARNESS_CHECK(SGRestartPending());
                HARNESS_CHECK([store objectForKey:SGKeyAppFont] == nil);
                break;
            case FontCheckCount: HARNESS_FAIL(@"unexpected scenario");
        }
        HARNESS_CHECK([SGRegisterCustomFont() isEqualToString:@"Chalkduster"]);
        HARNESS_CHECK([UIFont fontNamesForFamilyName:@"Chalkduster"].count > 0);
        HARNESS_CHECK([NSUserDefaults.standardUserDefaults arrayForKey:SGKeyAppFontFiles].count == 1);
        if (++scenario < FontCheckCount) {
            runImport();
            return;
        }
        method_setImplementation(copyMethod, originalCopy);
        imp_removeBlock(blockedCopy);
        NSLog(@"[harness] PASS font selection: enum/family/library changes and unset-start restart preserved; untouched choices select Custom; imported family available in all cases");
        fflush(NULL);
        exit(0);
    } copy] forKey:@"done"];
    UIDocumentPickerViewController *controller = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeFont] asCopy:YES];
    [picker documentPicker:controller didPickDocumentsAtURLs:@[fixture]];
}

void SGCheckFontSelection(void) {
    CTFontRef font = CTFontCreateWithName(CFSTR("Chalkduster"), 14, NULL);
    NSString *family = CFBridgingRelease(CTFontCopyFamilyName(font));
    fixture = CFBridgingRelease(CTFontCopyAttribute(font, kCTFontURLAttribute));
    CFRelease(font);
    HARNESS_CHECK([family isEqualToString:@"Chalkduster"] && fixture.isFileURL);
    copyMethod = class_getInstanceMethod(NSFileManager.class, @selector(copyItemAtURL:toURL:error:));
    originalCopy = method_getImplementation(copyMethod);
    blockedCopy = imp_implementationWithBlock(^BOOL(NSFileManager *files, NSURL *source, NSURL *destination, NSError **error) {
        if ([source isEqual:fixture]) {
            HARNESS_CHECK(!NSThread.isMainThread);
            dispatch_semaphore_t chosen = dispatch_semaphore_create(0);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (scenario == PickNewYork) {
                    // Real, still-enabled built-in row action while the import's copy is pending.
                    [page tableView:page.tableView didSelectRowAtIndexPath:
                        [NSIndexPath indexPathForRow:SGAppFontSerif inSection:0]];
                    HARNESS_CHECK(SGAppFontChosen() == SGAppFontSerif);
                } else if (scenario == RemovePreference) {
                    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyAppFont];
                } else if (scenario == RestorePreference) {
                    [NSUserDefaults.standardUserDefaults setObject:@(SGAppFontRounded) forKey:SGKeyAppFont];
                } else if (scenario == SwitchFamily) {
                    [page tableView:page.tableView didSelectRowAtIndexPath:
                        [NSIndexPath indexPathForRow:1 inSection:1]]; // Georgia in the harness's More fonts.
                } else if (scenario == SwitchLibrary) {
                    [NSUserDefaults.standardUserDefaults setObject:@"fixture-library-b" forKey:SGKeyAppFontLibrary];
                } else if (scenario == RestartUnsetPreference) {
                    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyAppFont];
                    SGRestartSpotify();
                }
                dispatch_semaphore_signal(chosen);
            });
            HARNESS_CHECK(dispatch_semaphore_wait(chosen, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
        }
        return ((BOOL (*)(id, SEL, id, id, NSError **))originalCopy)(files, @selector(copyItemAtURL:toURL:error:), source, destination, error);
    });
    method_setImplementation(copyMethod, blockedCopy);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        HARNESS_FAIL(@"font import did not complete");
    });
    runImport();
}
