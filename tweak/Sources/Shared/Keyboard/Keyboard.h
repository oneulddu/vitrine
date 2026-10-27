// The hardware keyboard's commands, and the grid its volume steps on, apart from the hooks that listen for
// them (Keyboard.x): the list with its inputs, modifiers and titles, and the volume math, are read by a check
// on the host as well.
#import <UIKit/UIKit.h>

// Which key a command is on. The arrows and Esc are named rather than spelled, because UIKit names them:
// their inputs are UIKeyInput…'s own strings, not characters.
typedef NS_ENUM(NSInteger, SGKeyboardKey) {
    SGKeyboardKeyCharacter = 0,   // `input` holds what is typed
    SGKeyboardKeyUp,
    SGKeyboardKeyDown,
    SGKeyboardKeyLeft,
    SGKeyboardKeyRight,
    SGKeyboardKeyEscape,
};

// What a command does, which is also its title in the ⌘-hold overlay. One command can be on two keys (Close
// the player is Esc and ⌘W), so the table names the command and the title is asked for by the command.
typedef NS_ENUM(NSInteger, SGKeyboardCommandID) {
    SGKeyboardCommandPlayPause = 0,
    SGKeyboardCommandNext,
    SGKeyboardCommandPrevious,
    SGKeyboardCommandLike,
    SGKeyboardCommandVolumeUp,
    SGKeyboardCommandVolumeDown,
    SGKeyboardCommandHome,
    SGKeyboardCommandSearch,
    SGKeyboardCommandLibrary,
    SGKeyboardCommandFind,
    SGKeyboardCommandClosePlayer,
};

// One key in -keyCommands.
typedef struct {
    SGKeyboardCommandID command;
    SGKeyboardKey key;
    __unsafe_unretained NSString *input;      // SGKeyboardKeyCharacter only
    UIKeyModifierFlags modifiers;
    __unsafe_unretained NSString *actionName;   // the %new method's selector's name
    BOOL needsSpace;   // offered only where Space is free: the focused control and VoiceOver have no use for it
} SGKeyboardCommand;

// The commands the mod adds, in the order the overlay lists them: SGKeyboardCommandCount of them.
const SGKeyboardCommand *SGKeyboardCommands(void);
NSUInteger SGKeyboardCommandCount(void);
// What the command's UIKeyCommand is made with: the arrows and Esc are UIKit's own input strings, the rest
// the characters typed.
NSString *SGKeyboardCommandInput(const SGKeyboardCommand *command);
// Its title, translated as every text of the mod's is: the ⌘-hold overlay's line for it.
NSString *SGKeyboardCommandTitle(SGKeyboardCommandID command);

// The system volume after one press, both ends 0–1: the 16-step grid's point above `volume` (`up`) or below
// it, 6.25 percentage points a step, clamped to 0–100%.
double SGKeyboardVolumeAfterStep(double volume, BOOL up);

#pragma mark - what covers the app's window

// A described window, for whether something covers the app's window. The screen a command acts on is Core's
// SGTopController; this is only the second line, for the menus and alerts that live in a window of their own.
typedef struct {
    NSInteger level;
    BOOL hidden;
    double alpha;
    BOOL sameScene;                            // in the app window's UIWindowScene
    CGRect frame;                              // in screen coordinates
    __unsafe_unretained NSString *className;
} SGKeyboardWindow;

// Whether one of `windows` covers `appFrame`, which stands at `appLevel`: above it, visible, opaque, in its scene,
// overlapping it, and not one of the system's keyboard and textbox windows, which are always there.
BOOL SGKeyboardWindowCovers(const SGKeyboardWindow *windows, NSUInteger count, NSInteger appLevel, CGRect appFrame);

#pragma mark - a delayed run that a later press cancels

// What a step of a run found. The run owns nothing of the app's: it asks, a beat apart, and stops at whichever answer
// is not "not yet".
typedef NS_ENUM(NSInteger, SGKeyboardRunStep) {
    SGKeyboardRunPress = 0,   // press `control`, then keep stepping
    SGKeyboardRunTake,        // the field is there: make it first responder unless it already is, then stop
    SGKeyboardRunWait,        // not up yet: step again, within the run's bound
    SGKeyboardRunStop,        // nothing to do, or the user has gone elsewhere
};

// A step's answer: the control to press, the responder to focus, or nothing.
typedef SGKeyboardRunStep (^SGKeyboardRunProbe)(UIControl **control, UIResponder **field);

// Starts a run of exactly `attempts` probes at most, the first `delay` seconds after this call and the rest `step`
// seconds apart, and returns the token that owns it. A `SGKeyboardRunPress` answer is carried out by `press`, which is
// the caller's own way of pressing its control. A run started later owns the work: every callback of an earlier run —
// the delayed first one included — asks SGKeyboardRunOwns first and does nothing when a later run has replaced it. The
// first probe is the run's own first step, so an activation and the waits after it are one ordered run and cannot race
// each other.
NSUInteger SGKeyboardRunBegin(SGKeyboardRunProbe probe, void (^press)(UIControl *control),
                              NSTimeInterval delay, NSTimeInterval step, NSInteger attempts);
// Whether the run of this token is still the one pending. The first thing every callback of a run asks.
BOOL SGKeyboardRunOwns(NSUInteger token);

// The %new methods Keyboard.x adds to UIApplication, named here so the table and the hooks agree.
@interface UIApplication (SGKeyboard)
- (void)sg_keyboardToggle:(UIKeyCommand *)key;
- (void)sg_keyboardNext:(UIKeyCommand *)key;
- (void)sg_keyboardPrevious:(UIKeyCommand *)key;
- (void)sg_keyboardLike:(UIKeyCommand *)key;
- (void)sg_keyboardVolumeUp:(UIKeyCommand *)key;
- (void)sg_keyboardVolumeDown:(UIKeyCommand *)key;
- (void)sg_keyboardHome:(UIKeyCommand *)key;
- (void)sg_keyboardSearch:(UIKeyCommand *)key;
- (void)sg_keyboardLibrary:(UIKeyCommand *)key;
- (void)sg_keyboardFind:(UIKeyCommand *)key;
- (void)sg_keyboardClosePlayer:(UIKeyCommand *)key;
@end
