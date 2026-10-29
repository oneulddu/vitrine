// Player redesign: the line of the lyrics being sung, one line under the cover, while the lyrics are not open
// in the player (PlayerLyricLine.x). A tap on it opens them, as the footer's lyrics glyph does.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

// On until switched off, read at launch; the Player page's Controls section has its row (PlayerSettings.m).
#define SGRKeyPlayerLyricLine @"spotifyglass.redesign.player.lyricLine"
BOOL SGRPlayerLyricLineOn(void);
// The line's place over the title in `view`'s coordinates while it has room there (it then shows whatever synced
// line is sung, unless the lyrics are open); CGRectNull while it has none, is off or the player is not up.
CGRect SGRPlayerLyricLineIn(UIView *view);
