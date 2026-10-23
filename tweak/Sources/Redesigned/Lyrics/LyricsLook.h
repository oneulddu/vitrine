// How the redesign's lyrics are set, from the Lyrics page: the size of the words, the room between two
// lines, how strongly the lines away from the one sung blur, and how strongly a held word glows and its
// letters wave. A preset sets all five, the sheet of sliders each one; they apply at once to every lyrics
// view there is, the Lyrics page's own preview among them (LyricsLookSettings.m).
#import <UIKit/UIKit.h>
#import "Shared/Lyrics/Lyrics.h"

// size and spacing in points; blur, glow and wave as shares of Apple Music's, 1 being theirs and 0 none.
typedef struct {
    CGFloat size, spacing, blur, glow, wave;
} SGRLyricsLook;

// The five as one dictionary; unset is the first preset, Apple Music's.
#define SGRKeyLyricsLook @"spotifyglass.redesign.lyricsLook"

// Posted on the main queue when the look changes; the object is whoever changed it, nil for none named.
extern NSNotificationName const SGRLyricsLookDidChangeNotification;

// Independent of the five look sliders. Missing or unknown IDs use the original drawing.
#define SGRKeyLyricsStyle @"spotifyglass.redesign.lyricsStyle"
typedef NS_ENUM(NSUInteger, SGRLyricsDrawingStyle) {
    SGRLyricsDrawingAppleMusic,
    SGRLyricsDrawingAurora,
    SGRLyricsDrawingNeon,
    SGRLyricsDrawingShimmer,
    SGRLyricsDrawingOutline,
};
extern NSNotificationName const SGRLyricsStyleDidChangeNotification;
NSArray<NSString *> *SGRLyricsStyleIDs(void);
NSString *SGRLyricsStyleNow(void);
SGRLyricsDrawingStyle SGRLyricsDrawingStyleForID(NSString *identifier);
NSString *SGRLyricsStyleName(NSString *identifier);
void SGRSetLyricsStyle(NSString *identifier);
UIMenu *SGRLyricsStyleMenu(NSString *title);
UIViewController *SGRLyricsStylesSettingsPage(void);

SGRLyricsLook SGRLyricsLookNow(void);
void SGRSetLyricsLook(SGRLyricsLook look, id changer);

// The presets, by name, Apple Music's first.
NSArray<NSString *> *SGRLyricsLookPresetNames(void);
SGRLyricsLook SGRLyricsLookPreset(NSUInteger index);
// The preset the look is, or -1 for a look of the sliders' own.
NSInteger SGRLyricsLookPresetIndex(SGRLyricsLook look);

// A few lines of the preview's own, words timed, one held long enough to glow and wave, and how long
// they take to come round again.
NSArray<SGKaraokeLine *> *SGRLyricsSampleLines(void);
NSInteger SGRLyricsSampleLength(void);
// The same timing in Korean, each line with a pronunciation and a translation, for the Text sizes page's preview.
NSArray<SGKaraokeLine *> *SGRLyricsSampleLinesWithExtras(void);

// LyricsLookSettings.m: the Lyrics page in the redesign, leading with the preview, the presets under it
// and their sliders in a sheet, then `sections`.
@class SGModSection;
UIViewController *SGRLyricsSettingsPage(NSString *title, NSString *intro, NSArray<SGModSection *> *sections);
