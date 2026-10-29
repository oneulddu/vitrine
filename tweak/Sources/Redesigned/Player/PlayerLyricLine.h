// Player redesign: the line of the lyrics being sung, one line under the cover, while the lyrics are not open
// in the player (PlayerLyricLine.x). A tap on it opens them, as the footer's lyrics glyph does.
//
// While the lyrics' own menu shows translations (SGRKeyLyricsTranslation), the line's translation sits under it,
// smaller and dimmer, when the room holds both (SGRPlayerLineFitIn); else the line shows alone, as without one.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>
#import "Shared/Lyrics/Lyrics.h"

// The translation shown under `line`: its own, trimmed, while translations are shown; nil with them off, without
// one, or for one that only repeats the line (SGLyricsShownTranslation).
static inline NSString *SGRPlayerLineTranslation(SGKaraokeLine *line, BOOL translationsShown) {
    if (!translationsShown || !line) return nil;
    NSString *translation = [SGLyricsShownTranslation(line) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return translation.length ? translation : nil;
}

// The line's place in a room `room` tall between the cover and the title. The line shows when the room holds its
// `lineHeight` and `margin` either side; the translation (`translationHeight`, 0 without one) goes under it only
// when the room holds both with the margins, else it is left out and the line alone keeps today's place. `height`
// is the view's: a tap's (`tapHeight`) or the pair's if taller, never more than the room.
typedef struct {
    BOOL line, translation;
    CGFloat height;
} SGRPlayerLineFit;
static inline SGRPlayerLineFit SGRPlayerLineFitIn(CGFloat room, CGFloat lineHeight, CGFloat translationHeight,
                                                  CGFloat margin, CGFloat tapHeight) {
    SGRPlayerLineFit fit = {NO, NO, 0};
    if (room < lineHeight + 2 * margin) return fit;
    fit.line = YES;
    CGFloat pair = lineHeight + translationHeight;
    fit.translation = translationHeight > 0 && room >= pair + 2 * margin;
    fit.height = MIN(MAX(tapHeight, fit.translation ? pair : 0), room);
    return fit;
}

// On until switched off, read at launch; the Player page's Controls section has its row (PlayerSettings.m).
#define SGRKeyPlayerLyricLine @"spotifyglass.redesign.player.lyricLine"
BOOL SGRPlayerLyricLineOn(void);
// The line's place over the title in `view`'s coordinates while it has room there (it then shows whatever synced
// line is sung, unless the lyrics are open); CGRectNull while it has none, is off or the player is not up.
CGRect SGRPlayerLyricLineIn(UIView *view);
