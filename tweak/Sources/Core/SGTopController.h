// The screen the app is showing, and whether a view of it is drawn: Spotify's own containers are not
// UITabBarController and UINavigationController, so the chain is followed the way the app builds it — what a
// controller presents, a navigation stack's top page, a tab bar's selected tab, else the child that covers more
// than half of a container's own view. The phone driver reads its `state` and `top` through this, and the
// keyboard's Esc and ⌘F are gated on it, so both see one answer.
#import <UIKit/UIKit.h>

// The app's front window: the key window among the visible ones at UIWindowLevelNormal, a FLEX window skipped.
UIWindow *SGAppWindow(void);

// Whether `view` is on screen: it has a window, nothing above it in the hierarchy is hidden or faded out, and its
// frame on screen has size and falls inside the window's bounds.
BOOL SGViewShown(UIView *view);
// `view`'s frame in screen coordinates.
CGRect SGViewScreenFrame(UIView *view);

// The controller the window shows: the deepest one the chain reaches, as described above. `path` and `presented`,
// when given, are filled with each controller's class name down the chain and with the class names of what was
// presented on the way. Both may be nil. nil without a window.
UIViewController *SGTopControllerInWindow(UIWindow *window, NSMutableArray<NSString *> *path,
                                          NSMutableArray<NSString *> *presented);

// What was presented on the way to that controller, outermost first, as the walk met it: the player's overlay, and
// whatever a page over the player presents. Empty when nothing is presented. The last one is what stands over
// everything the app shows; a controller merely containing a page is not in here, which is how a pushed page and a
// presented one are told apart.
NSArray<UIViewController *> *SGPresentedControllersInWindow(UIWindow *window);

// The player's own close control, found only where it really is: the resolver's *last presented* controller is the
// player's overlay, and the control carries one of `identifiers` in that overlay's own view. A sheet, a menu or an
// alert presented over the player becomes the last presented one, and this then answers nil — so Esc and ⌘W leave
// such a screen to itself. The resolved top is deliberately not searched: the player's topmost content is a
// full-screen background plane the controls are not inside. nil without a presentation or without the control.
UIView *SGPlayerCloseControlInWindow(UIWindow *window, NSArray<NSString *> *identifiers);

// The field of the search input page a Search bar's press pushed, from `browse` — the page whose bar was pressed:
// the front must be a page whose view is Spotify's SearchUI container (its identifier starts with
// "SearchUIContainerViewController"), pushed on the same navigation stack as `browse` with `browse` still under it,
// and the field is the shown view with `fieldIdentifier` that can take the cursor. A sheet or anything else that
// merely descends from the search is not it, so this answers nil then. nil if `browse` is nil.
UIResponder *SGSearchInputFieldInPushedPage(UIWindow *window, UIViewController *browse,
                                           NSString *containerIdentifierPrefix, NSString *fieldIdentifier);
