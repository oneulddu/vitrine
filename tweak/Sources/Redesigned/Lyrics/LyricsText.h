// What the redesign's lyrics show of a line besides its words: the pronunciation and the translation a
// source has for it (Shared/Lyrics/Lyrics.h), each switched on from the lyrics' own menu, and the order
// of sizes the three are set in, from the Lyrics page. The switches apply at once, to every lyrics
// view there is, and are kept for the next song and the next launch.
#import <UIKit/UIKit.h>

// A line's three texts. The order puts them largest first; the lyrics are always among them.
typedef NS_ENUM(NSInteger, SGRLyricsText) {
    SGRLyricsTextLyrics = 0,
    SGRLyricsTextPronunciation,
    SGRLyricsTextTranslation,
};

#define SGRKeyLyricsPronunciation @"spotifyglass.redesign.lyricsPronunciation"   // off until switched on
#define SGRKeyLyricsTranslation @"spotifyglass.redesign.lyricsTranslation"       // off until switched on
// The dots holding an instrumental break are named beside them: Intro, Interlude, Outro. Off until switched on.
#define SGRKeyLyricsBreakLabels @"spotifyglass.redesign.lyrics.breakLabels"
// The three as the words "lyrics", "pronunciation" and "translation", largest first.
#define SGRKeyLyricsTextOrder @"spotifyglass.redesign.lyricsTextOrder"

// Posted on the main queue when either switch or the order changes.
extern NSNotificationName const SGRLyricsTextDidChangeNotification;

// The order, SGRLyricsText values largest first; unset is Apple Music's: lyrics, pronunciation, translation.
NSArray<NSNumber *> *SGRLyricsTextOrder(void);
void SGRSetLyricsTextOrder(NSArray<NSNumber *> *order);
NSString *SGRLyricsTextName(SGRLyricsText text);
void SGRSetLyricsTextShown(SGRLyricsText text, BOOL shown);

// How each of the three is set on top of its place's size: a share of that size, a weight and, for the
// pronunciation and the translation, a share of their usual brightness. The lyrics keep theirs, so the sung
// words stay as bright against the waiting ones as ever. A value not stored, out of its range or off its step
// is the usual one: 100%, bold for the lyrics and the pronunciation, semibold for the translation.
typedef struct {
    NSInteger scale;        // percent of the place's size, 80 to 130 in fives
    NSInteger weight;       // 0 regular, 1 semibold, 2 bold
    NSInteger brightness;   // percent of the usual brightness, 40 to 140 in tens; the lyrics' is always 100
} SGRLyricsTextLook;

// Each part under its own key: SGRKeyLyricsTextLook ".lyrics.scale", ".translation.brightness" and so on.
#define SGRKeyLyricsTextLook @"spotifyglass.redesign.lyricsTextLook"

SGRLyricsTextLook SGRLyricsTextLookOf(SGRLyricsText text);
SGRLyricsTextLook SGRLyricsTextLookDefault(SGRLyricsText text);
BOOL SGRLyricsTextLookIsDefault(SGRLyricsText text);
// Stores it, a usual value as no value at all, and posts SGRLyricsTextDidChangeNotification.
void SGRSetLyricsTextLook(SGRLyricsText text, SGRLyricsTextLook look);
UIFontWeight SGRLyricsTextFontWeight(NSInteger weight);
NSArray<NSString *> *SGRLyricsTextWeightNames(void);   // by weight, regular first

// LyricsTextSettings.m: the Lyrics page's row for the order, which opens a list of the three to drag.
@class SGModRow;
SGModRow *SGRLyricsTextSizesRow(void);
// The page a row of that list opens: one text's size, weight and brightness under a pinned preview.
UIViewController *SGRLyricsTextLookPage(SGRLyricsText text);
