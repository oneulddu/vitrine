// What the harness does not compile: the accent hook (SGRAccent.x) and the repaint hook (SGRRepaint.x).
#import <UIKit/UIKit.h>
UIColor *SGRAccentColor(void) { return nil; }
__weak UIView *sgr_nowPlayingRoot = nil;
NSHashTable<UIView *> *sgr_nowPlayingPainted = nil;
__weak UIView *sgr_lyricsCardRoot = nil;
__weak UIView *sgr_lyricsPageRoot = nil;
__weak UIView *sgr_playlistRoot = nil;
__weak UIView *sgr_albumRoot = nil;

// Redesigned/Kit/SGRBridges.x: SGRField.m asks whether the player is opening or closing for its moving field.
BOOL SGRPlayerIsTransitioning(void) { return NO; }
void SGRObservePlayerTransition(id owner, void (^changed)(id owner)) {}

// Shared/Fonts/FontImport.m: no font of the user's own in the harness.
NSString *SGRegisterCustomFont(void) { return nil; }

// MotionSources.m: Apple Music is on, as it is by default.
BOOL SGMotionAppleMusicOn(void) { return YES; }

// ListeningStats.x: the album's play counts read a log of the harness's own, in its temporary folder.
#import "Shared/ListeningStats/SGPlayLog.h"
SGPlayLog *SGListeningLog(void) {
    static SGPlayLog *log;
    if (!log) log = [[SGPlayLog alloc] initWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"plays.tsv"]];
    return log;
}

// Shared/AlbumQueue/AlbumQueueMenu.x: the ⋯ menu's album queue is a part of a native menu, not of the page.
void SGAlbumQueueMarkSource(UIView *view) {}

// SGPageStyle.m: the cover viewer is presented over whatever is on top of the harness's window.
UIViewController *SGTopController(void) {
    UIWindowScene *scene = (UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject;
    UIViewController *top = scene.windows.firstObject.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}
