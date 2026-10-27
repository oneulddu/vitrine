// Hardware keyboard commands for either look. UIApplication is the end of the responder chain, so these
// work without making a player view first responder or taking focus from search.
//
// The commands are the table in KeyboardCommands.m (Keyboard.h), so what is on the keyboard is read there
// rather than in the hooks: Space, ⌘→/⌘← and ⌘L playback and collection, ⌘↑/⌘↓ the system volume a 16-step
// grid at a time, ⌘1/⌘2/⌘3 the Home, Search and Library destinations, ⌘F Search with its field focused,
// and Esc/⌘W the player's own close. Nothing here adds a switch: the shortcuts have none (the spec's
// decision), so pressing one does what it says, and each is skipped while text is being edited.
//
// Actions on the app's screens are taken by the screens' own views, never imitated: the volume is the
// system's, through the slider of one MPVolumeView kept off screen; the destinations go to Spotify's link
// dispatcher, asked first whether it has a handler for the URI (Shared/Navigation/Links.h), so a
// destination this build has not got does nothing instead of raising Spotify's "Couldn't open link"
// alert; and the player closes by its own header button, pressed.
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import "Core/SGTopController.h"
#import "Core/SGViewTree.h"
#import "Keyboard.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Navigation/Links.h"
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

static UIKeyCommand *command(const SGKeyboardCommand *spec) {
    UIKeyCommand *key = [UIKeyCommand keyCommandWithInput:SGKeyboardCommandInput(spec) modifierFlags:spec->modifiers action:NSSelectorFromString(spec->actionName)];
    key.discoverabilityTitle = SGKeyboardCommandTitle(spec->command);
    // None of these takes a key away from the system: Esc is the system's own cancel key, so a sheet that is up
    // closes on it rather than the player behind it, and what is ours is answered only where nothing else is.
    key.wantsPriorityOverSystemBehavior = NO;
    return key;
}

// Made once: the titles are fixed for the launch, and -keyCommands is asked on every key press.
static NSArray<UIKeyCommand *> *reportCommands(void) {
    static NSArray<UIKeyCommand *> *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<UIKeyCommand *> *made = [NSMutableArray array];
        const SGKeyboardCommand *table = SGKeyboardCommands();
        for (NSUInteger i = 0; i < SGKeyboardCommandCount(); i++) [made addObject:command(&table[i])];
        keys = made;
    });
    return keys;
}

#pragma mark - windows and what is on them

// The screen the app is showing, Core's resolver (SGTopController.h): the phone driver reads the same chain, so what
// the keyboard acts on and what the driver reports can never drift apart.
static UIViewController *frontViewController(UIWindow *window) {
    return SGTopControllerInWindow(window, nil, nil);
}

// Whether a window of its own stands over the app window and covers it now, read the way SGKeyboardWindowCovers
// reads a described list: same scene, above the app's level, visible, opaque, overlapping the screen — and not one
// of the system's keyboard and text-effects windows, which are up whenever a keyboard or accessory is and cover
// nothing the user is looking at. This is for the menus and alerts that live in a window of their own; sheets and
// alerts presented as controllers are the resolver's business.
static BOOL coveredByAnotherWindow(UIWindow *window) {
    NSArray<UIWindow *> *others = window.windowScene.windows;
    NSUInteger count = others.count;
    SGKeyboardWindow *described = count ? calloc(count, sizeof *described) : NULL;
    if (count && !described) return NO;
    for (NSUInteger i = 0; i < count; i++) {
        UIWindow *other = others[i];
        described[i] = (SGKeyboardWindow){
            .level = other.windowLevel,
            .hidden = other.hidden || other == window,
            .alpha = other.alpha,
            .sameScene = other.windowScene == window.windowScene,
            .frame = [other convertRect:other.bounds toWindow:nil],
            .className = NSStringFromClass(other.class) ?: @"",
        };
    }
    BOOL covered = SGKeyboardWindowCovers(described, count, window.windowLevel, [window convertRect:window.bounds toWindow:nil]);
    free(described);
    return covered;
}

// Whether `view` is drawn on `window` now: in it, nothing above it hidden or faded out, and big enough on
// the screen to be a control rather than a leftover.
static BOOL onScreen(UIView *view, UIWindow *window) {
    if (!view || !window || view.window != window || view.alpha < 0.01) return NO;
    if (!SGViewShown(view)) return NO;
    CGRect frame = [view convertRect:view.bounds toView:window];
    return frame.size.width >= 20 && frame.size.height >= 20 && CGRectIntersectsRect(frame, window.bounds);
}

// A press on a control of Spotify's, the way a tap on it arrives: its primary action's handlers or its touch
// up inside ones, and its accessibility activation when it answers to neither.
static BOOL pressControl(UIControl *control) {
    __block UIControlEvents handled = 0;
    if ([control respondsToSelector:@selector(enumerateEventHandlers:)]) {
        [control enumerateEventHandlers:^(UIAction *action, id target, SEL selector, UIControlEvents events, BOOL *stop) {
            handled |= events;
        }];
    }
    if (handled & UIControlEventPrimaryActionTriggered) {
        [control sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
        return YES;
    }
    if (handled & UIControlEventTouchUpInside) {
        [control sendActionsForControlEvents:UIControlEventTouchUpInside];
        return YES;
    }
    return [control accessibilityActivate];
}

#pragma mark - volume

// The one MPVolumeView, off screen: its slider is the system volume's, so a press moves the volume the way
// the hardware buttons do, and nothing here sends a volume command to a Connect device.
static MPVolumeView *sg_volumeView;

static UISlider *volumeSlider(void) {
    UIWindow *window = SGAppWindow();
    if (!window) return nil;
    if (!sg_volumeView) {
        sg_volumeView = [[MPVolumeView alloc] initWithFrame:CGRectMake(-1000, -1000, 40, 40)];
        sg_volumeView.userInteractionEnabled = NO;
        sg_volumeView.isAccessibilityElement = NO;
        sg_volumeView.accessibilityElementsHidden = YES;
    }
    if (sg_volumeView.window != window) {
        [sg_volumeView removeFromSuperview];
        [window addSubview:sg_volumeView];
    }
    // The view makes its slider in its own layout pass, which the system volume then keeps in step.
    [sg_volumeView layoutIfNeeded];
    for (UIView *subview in sg_volumeView.subviews) {
        if ([subview isKindOfClass:UISlider.class]) return (UISlider *)subview;
    }
    return nil;
}

static void stepVolume(BOOL up) {
    UISlider *slider = volumeSlider();
    if (!slider) return;   // no slider, nothing happens
    // MPVolumeView's slider is the system's: setting its value sets the volume, no event needed.
    slider.value = (float)SGKeyboardVolumeAfterStep(AVAudioSession.sharedInstance.outputVolume, up);
}

#pragma mark - destinations

// A destination opens only when Spotify has a handler for its URI, asked before the dispatcher is used
// (Shared/Navigation/Links.h): a build without that destination does nothing rather than raising the app's
// "Couldn't open link" alert. Not knowing is not absence — the registry can be unreadable before the app is
// up — so the dispatcher is then given its chance, and it answers for itself.
static BOOL openDestination(NSString *uri) {
    NSURL *url = [NSURL URLWithString:uri];
    if (SGSpotifyURIRoute(url, NULL) == SGLinkRouteNone) return NO;
    return SGOpenSpotifyURI(url);
}

// Whether `view` lies in `root`'s own view hierarchy, itself included.
static BOOL inHierarchy(UIView *view, UIView *root) {
    return view != nil && root != nil && (view == root || [view isDescendantOfView:root]);
}

// Search's page, as Spotify draws it: the page controller the resolver reaches on the Search tab, which is
// BrowsePageViewController, carries a shown view whose identifier starts with SearchHeaderFind — the bar is an
// Encore tertiary button, not a text field, and tapping it is what opens the input page. The bar and every other
// part are looked for inside that page's own hierarchy, so a Search behind another tab or under a sheet, whose
// views are not on screen, is never the one acted on.
static UIControl *searchBarIn(UIViewController *page, UIWindow *window) {
    UIView *root = page.viewIfLoaded;
    if (!root) return nil;
    __block UIControl *bar = nil;
    __block BOOL titled = NO;   // the page's own Search header, drawn: what says this is Search at all
    SGForEachView(root, ^(UIView *view) {
        if (!SGViewShown(view) || !inHierarchy(view, root)) return;
        BOOL header = [view.accessibilityIdentifier hasPrefix:@"SearchHeaderFind."];
        if (!header) return;
        titled = YES;
        if (!bar && [view isKindOfClass:UIControl.class] && [view.accessibilityIdentifier isEqualToString:@"SearchHeaderFind.SearchBar"]) bar = (UIControl *)view;
    });
    return titled ? bar : nil;
}

// The input page the Search bar's press pushes: Spotify's SearchUIContainerViewController page, on the same stack as
// the Browse page whose bar was pressed, with the field Spotify's own text view inside it (`SearchBarSearch.TextField`
// — not a UITextField). Both rules live in Core with the resolver (SGSearchInputFieldInPushedPage), so the harness
// exercises them.
static NSString *const kSearchInputPage = @"SearchUIContainerViewController";
static NSString *const kSearchInputField = @"SearchBarSearch.TextField";

// Which ⌘F is pending, as the token of its run (Core's SGKeyboardRunBegin): a second ⌘F starts a run of its own, and
// the earlier one's delay and steps then do nothing at all. The window and the Browse page are held weakly, so a
// pending run keeps neither alive, and a page that is gone ends its own run.
static __weak UIWindow *sg_searchWindow;
static __weak UIViewController *sg_searchBrowse;
// Whether this ⌘F's bar has been pressed: until it has, a step finds no input page and there is nothing to wait for.
static BOOL sg_searchPressed;

// ⌘F's run: one ordered run of kSearchFocusAttempts probes, the first of them the activation — the Browse page's bar
// pressed, which pushes Spotify's search input page — and every one after it looking for that page's field. Because
// the press is the run's own first probe, there is no second callback racing it: the field steps cannot run before the
// press, and a press cannot happen with no steps left. Each probe asks the run engine's ownership first
// (SGKeyboardRunOwns), so a replaced ⌘F presses nothing and looks nothing up, then the window-cover guard and the page.
static const NSTimeInterval kSearchFocusDelay = 0.45;
static const NSTimeInterval kSearchFocusStep = 0.1;
static const NSInteger kSearchFocusAttempts = 10;

static SGKeyboardRunStep searchFocusProbe(UIControl **control, UIResponder **field) {
    UIWindow *window = sg_searchWindow;
    if (!window) return SGKeyboardRunStop;
    // A menu or an alert in a window of its own is what the user has, at every step of the run.
    if (coveredByAnotherWindow(window)) return SGKeyboardRunStop;
    if (!sg_searchPressed) {
        // The run's first step: the page in front has to be the Browse page itself — its bar, drawn, is what says so.
        // Another tab, a sheet or a pushed page leaves the run with nothing to press, which is the do-nothing of a
        // Search that is not front at fire time.
        UIViewController *browse = frontViewController(window);
        UIControl *bar = browse ? searchBarIn(browse, window) : nil;
        if (!bar) return SGKeyboardRunStop;
        sg_searchBrowse = browse;
        sg_searchPressed = YES;
        *control = bar;
        return SGKeyboardRunPress;
    }
    UIViewController *browse = sg_searchBrowse;   // promoted from the weak store: a live page, or nil
    if (!browse) return SGKeyboardRunStop;
    // Only the page the press produced is accepted, on the Browse page's own navigation stack (Core's rule).
    UIResponder *input = SGSearchInputFieldInPushedPage(window, browse, kSearchInputPage, kSearchInputField);
    if (!input) return SGKeyboardRunWait;   // the input page is still coming up
    *field = input;
    return SGKeyboardRunTake;
}


#pragma mark - the player's close

// The player is looked for at most this often while no close button is cached.
static const CFTimeInterval kCloseLookInterval = 0.3;
static CFTimeInterval sg_closeLookedAt;
static __weak UIControl *sg_playerClose;

// The player's own close button while the player is up and nothing is over it. Core's SGPlayerCloseControlInWindow
// finds it in the *last presented* controller's view — the player is a presentation of its own, and its topmost
// content is a full-screen background plane the controls are not inside — so a sheet, a menu or an alert presented
// over the player makes this answer nil and Esc and ⌘W leave it to the system and its own dismissal. No window may
// cover the app's own either. The cached button is put through the same tests before it is used, and, since it costs
// nothing, so is the one just found.
static NSArray<NSString *> *playerCloseIdentifiers(void) {
    return @[@"now-playing-minimize-button", @"mobile-nowplaying-close-button"];
}

static UIControl *visiblePlayerClose(UIWindow *window) {
    if (coveredByAnotherWindow(window)) return nil;
    UIControl *cached = sg_playerClose;
    UIViewController *overlay = SGPresentedControllersInWindow(window).lastObject;
    UIView *root = overlay.viewIfLoaded;
    if (onScreen(cached, window) && inHierarchy(cached, root)) return cached;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - sg_closeLookedAt < kCloseLookInterval) return nil;
    sg_closeLookedAt = now;
    UIView *found = SGPlayerCloseControlInWindow(window, playerCloseIdentifiers());
    sg_playerClose = [found isKindOfClass:UIControl.class] ? (UIControl *)found : nil;
    // The cache is only a shortcut: a control the resolver just found still has to be on screen to be pressed.
    return onScreen(sg_playerClose, window) ? sg_playerClose : nil;
}

%hook UIApplication
// While text is being edited none of these is offered, which is how every one of them is skipped then; Space is
// offered only where it is free as well, and the playback handlers ask both again for themselves, as they
// always have.
- (NSArray<UIKeyCommand *> *)keyCommands {
    NSArray<UIKeyCommand *> *original = %orig;
    if (editingText()) return original;
    NSMutableArray<UIKeyCommand *> *keys = original ? [original mutableCopy] : [NSMutableArray array];
    const SGKeyboardCommand *table = SGKeyboardCommands();
    NSArray<UIKeyCommand *> *commands = reportCommands();
    BOOL space = spaceAllowed();
    for (NSUInteger i = 0; i < commands.count; i++) {
        if (table[i].needsSpace && !space) continue;
        [keys addObject:commands[i]];
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

%new
- (void)sg_keyboardVolumeUp:(UIKeyCommand *)key {
    stepVolume(YES);
}

%new
- (void)sg_keyboardVolumeDown:(UIKeyCommand *)key {
    stepVolume(NO);
}

%new
- (void)sg_keyboardHome:(UIKeyCommand *)key {
    openDestination(@"spotify:home");
}

%new
- (void)sg_keyboardSearch:(UIKeyCommand *)key {
    openDestination(@"spotify:search");
}

%new
- (void)sg_keyboardLibrary:(UIKeyCommand *)key {
    openDestination(@"spotify:collection");
}

// ⌘F: Search opened, and 450 ms later its bar pressed and the input page's field taken (beginSearchFocus), unless the
// user is somewhere else by then. A second ⌘F starts a run of its own, so the earlier run's delay and steps ask
// SGKeyboardRunOwns first and do nothing at all.
%new
- (void)sg_keyboardFind:(UIKeyCommand *)key {
    UIWindow *window = SGAppWindow();
    if (!window) return;
    sg_searchWindow = window;
    sg_searchBrowse = nil;   // nothing is pressed yet, and any page of the last press is not this one's
    sg_searchPressed = NO;
    if (!openDestination(@"spotify:search")) return;
    // The run owns the work from here, its first step being the press: a later ⌘F starts its own run, and this one's
    // delay and every step of it then do nothing. Its presses go through the app's own way of pressing a control.
    SGKeyboardRunBegin(^SGKeyboardRunStep(UIControl **control, UIResponder **field) {
        return searchFocusProbe(control, field);
    }, ^(UIControl *control) {
        pressControl(control);
    }, kSearchFocusDelay, kSearchFocusStep, kSearchFocusAttempts);
}

%new
- (void)sg_keyboardClosePlayer:(UIKeyCommand *)key {
    UIControl *close = visiblePlayerClose(SGAppWindow());
    if (close) pressControl(close);
}
%end

// No UI-mode gate: the transport, volume, destination and close commands are behavior shared by both looks.
%ctor {
    %init;
}
