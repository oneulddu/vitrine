// The now playing bar's rows of the redesign, the Mini player section of the Player page
// (Redesigned/Player/PlayerSettings.m puts them there).
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Redesigned/Navbar/Navbar.h"
#import "NowPlayingBar.h"

NSArray<SGModRow *> *SGRNowPlayingBarRows(void) {
    // The tab bar reads the switch as each scroll goes; a bar minimized when it goes off grows back at once.
    SGModRow *minimize = SGSwitchRow(SGL(@"settings.nowplayingbar.minimize.title", @"Apple Music style"), SGL(@"settings.nowplayingbar.minimize.subtitle", @"Between two tabs as a page scrolls down"), SGRKeyNavbarMinimize);
    minimize.changed = ^(BOOL on) {
        if (!on) SGRSetTabBarMinimized(NO, NO);
        SGRRefreshTabBar();
    };
    SGModRow *inlineConnect = SGOptionRow(SGL(@"settings.nowplayingbar.device_button.title", @"Device button"), SGL(@"settings.nowplayingbar.device_button.subtitle", @"Kept on the bar between the tabs"), SGRKeyBarInlineConnect);
    inlineConnect.waitsOn = SGRKeyNavbarMinimize;
    return @[
        minimize,
        inlineConnect,
        SGHideRow(SGL(@"settings.nowplayingbar.hide_device_button.title", @"Hide the device button"), SGL(@"settings.nowplayingbar.hide_device_button.subtitle", @"On the full now playing bar"), SGRHideBarConnect),
        // Spotify's own flag for the bar's save button, forced off: Spotify leaves the button out.
        SGKillRow(SGL(@"settings.nowplayingbar.hide_like.title", @"Hide the like button"), @"ios-feature-nowplayingbar.add_button"),
    ];
}
