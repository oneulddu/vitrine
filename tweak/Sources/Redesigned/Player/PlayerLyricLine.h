// Player redesign: the line of the lyrics being sung, one line under the cover, while the lyrics are not open
// in the player (PlayerLyricLine.x). A tap on it opens them, as the footer's lyrics glyph does.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

// On until switched off, read at launch; the Player page's Controls section has its row (PlayerSettings.m).
#define SGRKeyPlayerLyricLine @"spotifyglass.redesign.player.lyricLine"
BOOL SGRPlayerLyricLineOn(void);
