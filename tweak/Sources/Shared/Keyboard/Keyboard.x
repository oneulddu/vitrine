// Hardware keyboard playback commands for either look. UIApplication is the end of the responder
// chain, so these work without making a player view first responder or taking focus from search.
#import <UIKit/UIKit.h>
#import "Core/SGLocalize.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/HeadGestures/HeadGestures.h"

static __weak UIResponder *sg_keyboardResponder;

@interface UIResponder (SGKeyboardFocus)
- (void)sg_keyboardFindResponder:(id)sender;
@end

@implementation UIResponder (SGKeyboardFocus)
- (void)sg_keyboardFindResponder:(id)sender {
    sg_keyboardResponder = self;
}
@end

static BOOL editingText(void) {
    sg_keyboardResponder = nil;
    [UIApplication.sharedApplication sendAction:@selector(sg_keyboardFindResponder:) to:nil from:nil forEvent:nil];
    UIResponder *responder = sg_keyboardResponder;
    return [responder isKindOfClass:UITextField.class] || [responder isKindOfClass:UITextView.class]
        || [responder isKindOfClass:UISearchBar.class] || [responder conformsToProtocol:@protocol(UITextInput)];
}

// Space belongs to the focused control (a checkmark, a segment, a switch) and to VoiceOver, so it is
// offered only where neither has a use for it. The ⌘ commands are the mod's own either way.
static BOOL spaceAllowed(void) {
    if (editingText()) return NO;
    if (UIAccessibilityIsVoiceOverRunning()) return NO;
    return ![sg_keyboardResponder isKindOfClass:UIControl.class];
}

static UIKeyCommand *command(NSString *input, UIKeyModifierFlags modifiers, SEL action, NSString *title) {
    UIKeyCommand *key = [UIKeyCommand keyCommandWithInput:input modifierFlags:modifiers action:action];
    key.discoverabilityTitle = title;
    key.wantsPriorityOverSystemBehavior = NO;
    return key;
}

// Made once: the titles are fixed for the launch, and -keyCommands is asked on every key press.
static UIKeyCommand *sg_spaceCommand;
static UIKeyCommand *sg_nextCommand;
static UIKeyCommand *sg_previousCommand;
static UIKeyCommand *sg_likeCommand;

static NSArray<UIKeyCommand *> *reportCommands(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sg_spaceCommand = command(@" ", 0, @selector(sg_keyboardToggle:), SGL(@"settings.keyboard.play_pause", @"Play or pause"));
        sg_nextCommand = command(UIKeyInputRightArrow, UIKeyModifierCommand, @selector(sg_keyboardNext:), SGL(@"settings.keyboard.next", @"Next track"));
        sg_previousCommand = command(UIKeyInputLeftArrow, UIKeyModifierCommand, @selector(sg_keyboardPrevious:), SGL(@"settings.keyboard.previous", @"Previous track"));
        sg_likeCommand = command(@"l", UIKeyModifierCommand, @selector(sg_keyboardLike:), SGL(@"settings.keyboard.like", @"Like current track"));
    });
    return @[sg_spaceCommand, sg_nextCommand, sg_previousCommand, sg_likeCommand];
}

%hook UIApplication
- (NSArray<UIKeyCommand *> *)keyCommands {
    NSArray<UIKeyCommand *> *original = %orig;
    if (editingText()) return original;
    NSMutableArray<UIKeyCommand *> *keys = original ? [original mutableCopy] : [NSMutableArray array];
    BOOL space = spaceAllowed();
    for (UIKeyCommand *key in reportCommands()) {
        if (key == sg_spaceCommand && !space) continue;
        [keys addObject:key];
    }
    return keys;
}

%new
- (void)sg_keyboardToggle:(UIKeyCommand *)key {
    if (!spaceAllowed()) return;
    id player = SGPlayerInstance();
    if (![player respondsToSelector:@selector(state)]) return;
    SPTPlayerState *state = [(id<SPTPlayer>)player state];
    if (!state) return;
    if (state.isPaused) [player resume:nil];
    else [player pause:nil];
}

%new
- (void)sg_keyboardNext:(UIKeyCommand *)key {
    id player = SGPlayerInstance();
    if (!editingText() && [player respondsToSelector:@selector(skipToNextTrack)]) [player skipToNextTrack];
}

%new
- (void)sg_keyboardPrevious:(UIKeyCommand *)key {
    id player = SGPlayerInstance();
    if (!editingText() && [player respondsToSelector:@selector(skipToPreviousTrackWithOptions:)]) [(id<SPTPlayer>)player skipToPreviousTrackWithOptions:nil];
}

%new
- (void)sg_keyboardLike:(UIKeyCommand *)key {
    if (!editingText()) SGLikePlayingTrack();
}
%end

// No UI-mode gate: transport and collection commands are behavior shared by both looks.
%ctor {
    %init;
}
