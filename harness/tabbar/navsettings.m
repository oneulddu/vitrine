// The Tab bar page (Redesigned/Navbar/NavbarSettings.m) over the harness's bar, `navsettings`: its fade switch starts
// on, its preview reads the fade, and flipping the switch takes the fade off the real bar under the page at once and
// out of the preview. The page is up from 1 s; on until 3.5 s and off until 6 s, for a screenshot of each.
#import <UIKit/UIKit.h>
#import "../harness-fail.h"
#import "Core/SGViewTree.h"
#import "Core/SGPrefs.h"
#import "Redesigned/Navbar/Navbar.h"

@class SGHarnessChrome;

static UISwitch *fadeSwitch(UIView *root) {
    __block UISwitch *found = nil;
    for (UITableViewCell *cell in ((UITableView *)root).visibleCells) {
        __block BOOL named = NO;
        SGForEachView(cell, ^(UIView *view) {
            if ([view isKindOfClass:UILabel.class] && [((UILabel *)view).text isEqualToString:@"Fade under the bar"]) named = YES;
        });
        if (named && [cell.accessoryView isKindOfClass:UISwitch.class]) found = (UISwitch *)cell.accessoryView;
    }
    return found;
}

static UIView *previewIn(UIView *root) {
    __block UIView *found = nil;
    SGForEachView(root, ^(UIView *view) {
        if (!found && [view.accessibilityLabel isEqualToString:@"Tab bar preview"]) found = view;
    });
    return found;
}

static void expectPreview(UIView *preview, BOOL on, NSString *moment) {
    if ([preview.accessibilityValue containsString:@"Fade under the bar"] != on) HARNESS_FAIL(@"%@: the preview reads \"%@\"", moment, preview.accessibilityValue);
    printf("PASS %s: the preview reads \"%s\"\n", moment.UTF8String, preview.accessibilityValue.UTF8String);
    fflush(stdout);
}

void SGHarnessRunNavbarPage(SGHarnessChrome *chrome, void (^barChecked)(BOOL on)) {
    UIViewController *owner = (UIViewController *)chrome;
    // What Navbar.x records off Spotify's bar, which the harness does not compile: the mock's tabs.
    SGRSetNavbarStock(@[@"Home", @"Search", @"Your Library", @"Create"]);
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:SGRNavbarSettingsPage()];
    nav.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [owner presentViewController:nav animated:NO completion:nil];
    [nav.view layoutIfNeeded];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    UITableView *table = ((UITableViewController *)nav.topViewController).tableView;
    UISwitch *toggle = fadeSwitch(table);
    UIView *preview = previewIn(table.tableHeaderView);
    if (!toggle || !toggle.on || !preview) HARNESS_FAIL(@"the fade switch %@, the preview %@", toggle ? (toggle.on ? @"on" : @"off") : @"missing", preview);
    expectPreview(preview, YES, @"switch on");
    barChecked(YES);
    printf("READY on\n");
    fflush(stdout);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        toggle.on = NO;
        [toggle sendActionsForControlEvents:UIControlEventValueChanged];
        if (SGEnabled(SGRKeyNavbarFade)) HARNESS_FAIL(@"the switch did not store %@", SGRKeyNavbarFade);
        [owner.view layoutIfNeeded];
        barChecked(NO);
        expectPreview(preview, NO, @"switch off");
        printf("READY off\n");
        fflush(stdout);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            printf("PASS all navsettings\n");
            fflush(stdout);
            exit(0);
        });
    });
}
