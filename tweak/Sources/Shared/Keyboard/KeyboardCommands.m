// The keyboard's commands, the volume's grid, and the reading of a described window list the commands are gated
// on, with no hook in sight: Keyboard.x makes UIKeyCommands from this list and answers them.
#import "Keyboard.h"
#import "Core/SGLocalize.h"
#import <math.h>

// The grid the volume steps on: 16 steps across the full range, 6.25 percentage points each.
enum { kVolumeSteps = 16 };
// A volume this close to a grid point is on it: the system reports a float, so 0.6875 can arrive as
// 11.000000000000002 steps, and a press must not then land back on the point it started from.
static const double kVolumeGridEpsilon = 1e-6;

double SGKeyboardVolumeAfterStep(double volume, BOOL up) {
    if (!(volume > 0)) volume = 0;   // negatives and NaN too
    if (volume > 1) volume = 1;
    double steps = volume * kVolumeSteps;
    double nearest = round(steps);
    BOOL onGrid = fabs(steps - nearest) < kVolumeGridEpsilon;
    // Off the grid, a press lands on the next point that way (the volume only ever snaps); on it, one whole
    // step further. Both ends are the grid's own, 0 and 100%, so a press there stays put.
    long index = onGrid ? (long)nearest + (up ? 1 : -1) : (long)(up ? ceil(steps) : floor(steps));
    if (index < 0) index = 0;
    if (index > kVolumeSteps) index = kVolumeSteps;
    return (double)index / kVolumeSteps;
}

static const SGKeyboardCommand kCommands[] = {
    {SGKeyboardCommandPlayPause, SGKeyboardKeyCharacter, @" ", 0, @"sg_keyboardToggle:", YES},
    {SGKeyboardCommandNext, SGKeyboardKeyRight, nil, UIKeyModifierCommand, @"sg_keyboardNext:", NO},
    {SGKeyboardCommandPrevious, SGKeyboardKeyLeft, nil, UIKeyModifierCommand, @"sg_keyboardPrevious:", NO},
    {SGKeyboardCommandLike, SGKeyboardKeyCharacter, @"l", UIKeyModifierCommand, @"sg_keyboardLike:", NO},
    {SGKeyboardCommandVolumeUp, SGKeyboardKeyUp, nil, UIKeyModifierCommand, @"sg_keyboardVolumeUp:", NO},
    {SGKeyboardCommandVolumeDown, SGKeyboardKeyDown, nil, UIKeyModifierCommand, @"sg_keyboardVolumeDown:", NO},
    {SGKeyboardCommandHome, SGKeyboardKeyCharacter, @"1", UIKeyModifierCommand, @"sg_keyboardHome:", NO},
    {SGKeyboardCommandSearch, SGKeyboardKeyCharacter, @"2", UIKeyModifierCommand, @"sg_keyboardSearch:", NO},
    {SGKeyboardCommandLibrary, SGKeyboardKeyCharacter, @"3", UIKeyModifierCommand, @"sg_keyboardLibrary:", NO},
    {SGKeyboardCommandFind, SGKeyboardKeyCharacter, @"f", UIKeyModifierCommand, @"sg_keyboardFind:", NO},
    {SGKeyboardCommandClosePlayer, SGKeyboardKeyEscape, nil, 0, @"sg_keyboardClosePlayer:", NO},
    {SGKeyboardCommandClosePlayer, SGKeyboardKeyCharacter, @"w", UIKeyModifierCommand, @"sg_keyboardClosePlayer:", NO},
};

const SGKeyboardCommand *SGKeyboardCommands(void) {
    return kCommands;
}

NSString *SGKeyboardCommandInput(const SGKeyboardCommand *command) {
    switch (command->key) {
        case SGKeyboardKeyUp: return UIKeyInputUpArrow;
        case SGKeyboardKeyDown: return UIKeyInputDownArrow;
        case SGKeyboardKeyLeft: return UIKeyInputLeftArrow;
        case SGKeyboardKeyRight: return UIKeyInputRightArrow;
        case SGKeyboardKeyEscape: return UIKeyInputEscape;
        case SGKeyboardKeyCharacter: break;
    }
    return command->input ?: @"";
}

NSUInteger SGKeyboardCommandCount(void) {
    return sizeof kCommands / sizeof kCommands[0];
}

#pragma mark - a delayed run that a later press cancels

// The token of the run that owns the work now. A run holds no reference to the app: only its probe, which stops when
// it answers SGKeyboardRunStop.
static NSUInteger sg_runToken;

static void runStep(NSUInteger token, SGKeyboardRunProbe probe, void (^press)(UIControl *), NSTimeInterval step, NSInteger left) {
    // First, before the probe looks at anything: is this still the run that owns the work?
    if (!SGKeyboardRunOwns(token)) return;
    // And before the probe runs: is there a step left to spend on it? `left` is what this step has, so a run of
    // `attempts` probes exactly that many times, and the last step is the last probe.
    if (left <= 0) return;
    UIControl *control = nil;
    UIResponder *field = nil;
    SGKeyboardRunStep answer = probe(&control, &field);
    switch (answer) {
        case SGKeyboardRunPress:
            if (control) {
                if (press) press(control);
                else [control sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
            }
            break;
        case SGKeyboardRunTake:
            if (field && !field.isFirstResponder) [field becomeFirstResponder];
            return;
        case SGKeyboardRunStop:
            return;
        case SGKeyboardRunWait:
            break;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(step * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        runStep(token, probe, press, step, left - 1);
    });
}

NSUInteger SGKeyboardRunBegin(SGKeyboardRunProbe probe, void (^press)(UIControl *), NSTimeInterval delay, NSTimeInterval step, NSInteger attempts) {
    NSUInteger token = ++sg_runToken;
    if (!probe) return token;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        runStep(token, probe, press, step, attempts);
    });
    return token;
}

BOOL SGKeyboardRunOwns(NSUInteger token) {
    return token == sg_runToken;
}


#pragma mark - what covers the app's window

// The system's own windows that stand over every app's without covering what the app shows: the keyboard, its
// text effects, the autocorrection/host windows and the like. They are present whenever a keyboard or an input
// accessory is up, so they say nothing about what the user is looking at.
static BOOL systemOverlayWindow(NSString *className) {
    static NSString *const names[] = {@"Keyboard", @"TextEffects", @"Autofill", @"InputWindow", @"RemoteTextInput"};
    for (size_t i = 0; i < sizeof names / sizeof names[0]; i++) {
        if ([className containsString:names[i]]) return YES;
    }
    return NO;
}

BOOL SGKeyboardWindowCovers(const SGKeyboardWindow *windows, NSUInteger count, NSInteger appLevel, CGRect appFrame) {
    for (NSUInteger i = 0; i < count; i++) {
        const SGKeyboardWindow *window = &windows[i];
        if (window->hidden || !(window->alpha > 0) || !window->sameScene) continue;
        if (window->level <= appLevel) continue;
        if (!CGRectIntersectsRect(window->frame, appFrame)) continue;
        if (systemOverlayWindow(window->className)) continue;
        return YES;
    }
    return NO;
}

// The ⌘-hold overlay's line for a command.
NSString *SGKeyboardCommandTitle(SGKeyboardCommandID command) {
    switch (command) {
        case SGKeyboardCommandPlayPause: return SGL(@"settings.keyboard.play_pause", @"Play or pause");
        case SGKeyboardCommandNext: return SGL(@"settings.keyboard.next", @"Next track");
        case SGKeyboardCommandPrevious: return SGL(@"settings.keyboard.previous", @"Previous track");
        case SGKeyboardCommandLike: return SGL(@"settings.keyboard.like", @"Like current track");
        case SGKeyboardCommandVolumeUp: return SGL(@"settings.keyboard.volume_up", @"Volume up");
        case SGKeyboardCommandVolumeDown: return SGL(@"settings.keyboard.volume_down", @"Volume down");
        case SGKeyboardCommandHome: return SGL(@"settings.keyboard.home", @"Go to Home");
        case SGKeyboardCommandSearch: return SGL(@"settings.keyboard.search", @"Go to Search");
        case SGKeyboardCommandLibrary: return SGL(@"settings.keyboard.library", @"Go to Library");
        case SGKeyboardCommandFind: return SGL(@"settings.keyboard.find", @"Search");
        case SGKeyboardCommandClosePlayer: return SGL(@"settings.keyboard.close_player", @"Close the player");
    }
    return @"";
}
