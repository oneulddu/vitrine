// What the harness does not compile: the accent hook (SGRAccent.x) and the repaint hook (SGRRepaint.x).
#import <UIKit/UIKit.h>
UIColor *SGRAccentColor(void) { return nil; }
__weak UIView *sgr_nowPlayingRoot = nil;
NSHashTable<UIView *> *sgr_nowPlayingPainted = nil;
__weak UIView *sgr_lyricsCardRoot = nil;
__weak UIView *sgr_lyricsPageRoot = nil;
__weak UIView *sgr_playlistRoot = nil;
__weak UIView *sgr_albumRoot = nil;
__weak UIView *sgr_artistRoot = nil;

// Redesigned/Kit/SGRBridges.x: SGRField.m asks whether the player is opening or closing for its moving field.
BOOL SGRPlayerIsTransitioning(void) { return NO; }
void SGRObservePlayerTransition(id owner, void (^changed)(id owner)) {}

// Shared/AlbumQueue/AlbumQueueMenu.x: a tapped album header ⋯ records its album for the menu; no menu here.
void SGAlbumQueueMarkSource(UIView *view) {}

// Shared/Player/SGLastTrack.m, which the preview cards' placeholder art comes from; a plain square of the tint here,
// without the player that file records.
UIImage *SGPlaceholderArtwork(UIColor *tint) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(64, 64)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [tint setFill];
        UIRectFill(CGRectMake(0, 0, 64, 64));
    }];
}
