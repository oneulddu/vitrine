// The press the Music app gives what a finger is on: a soft round platter behind a control's glyph with
// the glyph sinking into it, a highlight behind a list row, and a watcher that tells a part of the redesign
// when a view of Spotify's is pressed and let go, so it can draw a press of its own (the now playing card).
//
// Every press here only watches touches. The watcher is a gesture recognizer that never recognizes: it
// takes no touch from the view, cancels none, delays none and prevents no other recognizer, so Spotify's
// own taps, swipe actions, context menus and scrolling run as they did; any of them that takes the touch
// ends the press. Spotify's controls stay where and what they were, whatever their class.
//
// Reduce Motion: nothing scales or moves; the platter and the highlight still fade in and out.
//
// Ownership: what a call makes belongs to the view it was made for (associated objects); Spotify's views
// are held weakly. Threading: main thread only.
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, SGRPressKind) {
    // A button's: pressed at the touch, let go when the finger drags out of reach and pressed again when it
    // comes back, tapped when it lifts within reach.
    SGRPressKindButton,
    // A list row's or a card's, on something that scrolls or swipes: pressed only once the finger has rested
    // a moment (the delay a table view waits before it highlights), never while the list is still gliding,
    // and over once the finger moves. A tap quicker than the delay still flashes the press.
    SGRPressKindScrolling,
};

// Watches touches on `view`: `begins` (optional) says whether a touch that starts there presses, and
// `changed` is called as the press comes and goes; `tapped` with the last change when the touch lifted where
// it counts. The watcher is made once per view; a second call replaces the kind and the blocks.
void SGRPressWatch(UIView *view, SGRPressKind kind, BOOL (^begins)(UITouch *touch), void (^changed)(BOOL pressed, BOOL tapped));

// Whether `touch` started on a small control inside `container` (a button on a card or a row, ⋯, a heart),
// which keeps its own press: the card or row around it does not take one then.
BOOL SGRPressOnSmallControl(UITouch *touch, UIView *container);

typedef NS_OPTIONS(NSUInteger, SGRPressOptions) {
    SGRPressScale = 1 << 0,         // the glyph sinks to 0.85 while pressed
    SGRPressNudgeBack = 1 << 1,     // a tap nudges it back, toward the leading arrow (previous)
    SGRPressNudgeForward = 1 << 2,  // or forward (next)
};

// A press for `glyph` drawn by touches on `control`: a platter `diameter` across fades in behind the glyph's
// middle, in `platterHost` (under the glyph when the glyph is in it, else at the bottom), and goes on release.
// A disabled control under the finger takes no press. Call it from every layout pass of the screen: it puts
// the platter back under the glyph and keeps the newest glyph; the platter and the watcher are made once.
void SGRPressGlyph(UIView *control, UIView *glyph, UIView *platterHost, CGFloat diameter, SGRPressOptions options);

// The highlight of a list row: a rounded white wash behind the cell's content while the row is pressed, the
// way a table view highlights its cells. `cell` is the collection view cell; `isRow` NO for a cell reused for
// something that is not a track row, which then takes no highlight. Call it from the cell's layout passes.
void SGRPressRow(UIView *cell, BOOL isRow);

// Moves `layer`'s `keyPath` to `value` on the press spring, from wherever it is drawn now; at once under
// Reduce Motion or with `animated` NO, which also drops a spring under way.
void SGRPressAnimateLayer(CALayer *layer, NSString *keyPath, id value, BOOL animated);
