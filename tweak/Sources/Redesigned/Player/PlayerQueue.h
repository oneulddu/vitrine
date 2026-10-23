// Player redesign: Playing Next, the tracks the player has to come (SPTPlayerState.future), as a dark sheet opened
// from the player's ⋯ menu (PlayerMenu.m). Spotify's own Queue button in the footer stays Spotify's.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

// Opens the sheet over what `from` (the ⋯) is in, once the menu it was picked from has gone; nothing while it is
// open already.
void SGRPlayerShowQueue(UIView *from);
