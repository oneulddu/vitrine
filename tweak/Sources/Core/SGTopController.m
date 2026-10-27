#import "SGTopController.h"

UIWindow *SGAppWindow(void) {
    UIWindow *found = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden || window.windowLevel != UIWindowLevelNormal) continue;
            if ([NSStringFromClass(window.class) containsString:@"FLEX"]) continue;
            if (!found || window.isKeyWindow) found = window;
        }
    }
    return found;
}

BOOL SGViewShown(UIView *view) {
    if (!view || !view.window) return NO;
    for (UIView *v = view; v; v = v.superview) {
        if (v.hidden || v.alpha < 0.01) return NO;
    }
    CGRect frame = [view convertRect:view.bounds toView:nil];
    return frame.size.width > 0 && frame.size.height > 0 && CGRectIntersectsRect(frame, view.window.bounds);
}

CGRect SGViewScreenFrame(UIView *view) {
    return [view.window convertRect:[view convertRect:view.bounds toView:nil] toWindow:nil];
}

// The child of a container that is on screen and covers more than half of the container's own view: Spotify's
// containers (the tab bar's, the player's) show one child full size with the others behind it, so covering most of
// it is what tells the shown one apart. A bar inside the container is under half of it, and is not taken.
static UIViewController *shownChild(UIViewController *container) {
    UIView *own = container.viewIfLoaded;
    if (!own) return nil;
    UIWindow *window = own.window;
    if (!window) return nil;
    CGRect bounds = window.bounds;
    CGRect mine = CGRectIntersection(SGViewScreenFrame(own), bounds);
    CGFloat best = mine.size.width * mine.size.height / 2;
    UIViewController *found = nil;
    for (UIViewController *child in container.childViewControllers) {
        if (!child.isViewLoaded || !SGViewShown(child.view)) continue;
        CGRect frame = CGRectIntersection(SGViewScreenFrame(child.view), bounds);
        CGFloat area = frame.size.width * frame.size.height;
        if (area <= best) continue;
        best = area;
        found = child;
    }
    return found;
}

// The walk, keeping the controllers themselves: Driver prints the class names, the keyboard needs to know what was
// presented and where a page was pushed.
static UIViewController *walk(UIWindow *window, NSMutableArray<UIViewController *> *controllers,
                              NSMutableArray<UIViewController *> *presentations) {
    UIViewController *top = window.rootViewController;
    // A chain of containers is short; the bound is only so a broken one cannot spin.
    for (NSUInteger guard = 0; top && guard < 64; guard++) {
        if (controllers) [controllers addObject:top];
        UIViewController *next = nil;
        if (top.presentedViewController && !top.presentedViewController.isBeingDismissed) {
            next = top.presentedViewController;
            if (presentations) [presentations addObject:next];
        } else if ([top isKindOfClass:UINavigationController.class]) {
            next = ((UINavigationController *)top).topViewController;
        } else if ([top isKindOfClass:UITabBarController.class]) {
            next = ((UITabBarController *)top).selectedViewController;
        } else {
            next = shownChild(top);
        }
        if (!next || next == top) break;
        top = next;
    }
    return top;
}

UIViewController *SGTopControllerInWindow(UIWindow *window, NSMutableArray<NSString *> *path,
                                          NSMutableArray<NSString *> *presented) {
    NSMutableArray<UIViewController *> *controllers = path ? [NSMutableArray array] : nil;
    NSMutableArray<UIViewController *> *presentations = presented ? [NSMutableArray array] : nil;
    UIViewController *top = walk(window, controllers, presentations);
    for (UIViewController *controller in controllers) [path addObject:NSStringFromClass(controller.class)];
    for (UIViewController *controller in presentations) [presented addObject:NSStringFromClass(controller.class)];
    return top;
}

NSArray<UIViewController *> *SGPresentedControllersInWindow(UIWindow *window) {
    NSMutableArray<UIViewController *> *presentations = [NSMutableArray array];
    walk(window, nil, presentations);
    return presentations;
}

UIView *SGPlayerCloseControlInWindow(UIWindow *window, NSArray<NSString *> *identifiers) {
    UIViewController *overlay = SGPresentedControllersInWindow(window).lastObject;
    UIView *root = overlay.viewIfLoaded;
    if (!root) return nil;
    __block UIView *found = nil;
    // Depth first, the first shown control whose identifier starts with one of the names (the app sets the plain
    // name, and a modifier may be appended).
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count && !found) {
        UIView *view = stack.firstObject;
        [stack removeObjectAtIndex:0];
        if ([view isKindOfClass:UIControl.class] && SGViewShown(view)) {
            for (NSString *identifier in identifiers) {
                if ([view.accessibilityIdentifier hasPrefix:identifier]) {
                    found = view;
                    break;
                }
            }
        }
        [stack addObjectsFromArray:view.subviews];
    }
    return found;
}

// Where `page` sits on `stack`: the index of the nearest controller on the way up that the stack holds. Spotify's pages
// are not stack members themselves — a hosting controller is, with the page under it — so the page is placed by the
// member that carries it. NSNotFound for a page the stack does not hold at all.
static NSUInteger stackIndexOf(UINavigationController *stack, UIViewController *page) {
    NSArray<UIViewController *> *members = stack.viewControllers;
    for (UIViewController *v = page; v; v = v.parentViewController) {
        NSUInteger index = [members indexOfObjectIdenticalTo:v];
        if (index != NSNotFound) {
            // The member carries the page: the page's place is that member's, and a page inside the member's own root
            // is below a page pushed after it.
            return index;
        }
    }
    return NSNotFound;
}

UIResponder *SGSearchInputFieldInPushedPage(UIWindow *window, UIViewController *browse,
                                           NSString *containerIdentifierPrefix, NSString *fieldIdentifier) {
    if (!browse) return nil;
    UIViewController *front = SGTopControllerInWindow(window, nil, nil);
    if (!front) return nil;
    // The navigation stack the bar was pressed on, if the Browse page sits in one.
    UINavigationController *stack = nil;
    for (UIViewController *v = browse; v; v = v.parentViewController) {
        if ([v isKindOfClass:UINavigationController.class]) { stack = (UINavigationController *)v; break; }
    }
    // Only the page the press produced: the input container, above the Browse page on that same stack.
    UIViewController *input = nil;
    for (UIViewController *page = front; page; page = page.parentViewController) {
        if (![page.viewIfLoaded.accessibilityIdentifier hasPrefix:containerIdentifierPrefix]) continue;
        if (!stack) {
            // A Browse page outside a navigation stack can only have pushed its input page as its own child.
            for (UIViewController *up = page.parentViewController; up; up = up.parentViewController) {
                if (up == browse) { input = page; break; }
            }
            if (input) break;
            continue;
        }
        NSUInteger own = stackIndexOf(stack, page);
        NSUInteger under = stackIndexOf(stack, browse);
        if (own == NSNotFound || under == NSNotFound) continue;
        if (own > under) { input = page; break; }
    }
    UIView *root = input.viewIfLoaded;
    if (!root) {
        // The input page is not up yet: a step of a run waits for it, and no field is answered meanwhile.
        return nil;
    }
    __block UIResponder *field = nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count && !field) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([view.accessibilityIdentifier isEqualToString:fieldIdentifier] && SGViewShown(view) && [view canBecomeFirstResponder]) {
            field = (UIResponder *)view;
            break;
        }
        [queue addObjectsFromArray:view.subviews];
    }
    return field;
}
