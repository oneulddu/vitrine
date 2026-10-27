// The redesign's accent color in place of Spotify's green (SGRAccent.x), chosen apart from the native
// look's and stored under its own key; unset is #37F200, negative keeps Spotify's own green.
#import <UIKit/UIKit.h>

#define SGRKeyAccent @"spotifyglass.redesign.accent"   // 0xRRGGBB
// The last color picked, kept while a preset is in place so Custom brings it back.
#define SGRKeyAccentCustom @"spotifyglass.redesign.accent.custom"
// The redesign's own green until another is picked; Spotify's is a pick of its own, stored as -1.
#define SGRDefaultAccent 0x37F200

UIColor *SGRAccentColor(void);   // nil while Spotify's own green is kept
NSInteger SGRAccentRGB(void);    // the color in effect, 0xRRGGBB, Spotify's green included
// What a UIColor made from these components comes out as: one of Spotify's greens turns into the accent while it is
// swapped. NO, and the components untouched, for any other color.
BOOL SGRAccentSwap(CGFloat *r, CGFloat *g, CGFloat *b);

// The colors chosen before, newest first, as 0xRRGGBB numbers (SGRAccentHistory.m), shown as swatches over the
// picker (SGRAccentSheet.m), apart from the native look's. The redesign's own green and Spotify's are never kept.
#define SGRKeyAccentRecent @"spotifyglass.redesign.accent.recent"
#define SGRAccentRecentLimit 8
// The stored list as it is shown: whole numbers in 0...0xFFFFFF, first of each only, the two greens and any other
// entry left out, at most SGRAccentRecentLimit.
NSArray<NSNumber *> *SGRAccentRecentFrom(id stored);
// `recent` after `rgb` was chosen with `current` in effect: unchanged when they are the same color or `rgb` is not
// kept, else `rgb` first, taken out of where it was, and the oldest past the limit dropped.
NSArray<NSNumber *> *SGRAccentRecentAdding(NSArray<NSNumber *> *recent, NSInteger rgb, NSInteger current);
// The accent color's sheet: `recent` as swatches over the system color picker, `current` marked. A swatch hands its
// color to `chosen` at once; the picker's color goes when its checkmark is tapped, never while it is dragged; closing
// the sheet chooses nothing.
void SGRPickAccent(NSString *title, NSInteger current, NSArray<NSNumber *> *recent, void (^chosen)(NSInteger rgb));

// Plain checkmark (SGRPlainCheck.x): a saved song's circled tick as a plain checkmark in the accent. Off until switched
// on, read at launch.
#define SGRKeyPlainCheck @"spotifyglass.redesign.plainCheck"
BOOL SGRPlainCheckOn(void);
// The plain checkmark's view, a template image: Follow the cover (Player/PlayerCoverAccent.x) sets its tint.
#define SGRPlainCheckIdentifier @"spotifyglass.plainCheck"

@class SGModRow;
NSArray<SGModRow *> *SGRAppearanceRows(void);   // the accent color, for the Appearance page
