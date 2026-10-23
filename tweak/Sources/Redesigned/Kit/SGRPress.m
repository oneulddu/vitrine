#import <UIKit/UIGestureRecognizerSubclass.h>
#import "Core/SGCore.h"
#import "SGRPress.h"
#import "SGRTokens.h"

// A scrolling press waits this long for the finger to rest, and is over once it moves this far: a scroll view
// waits about as long before it hands a touch to what is under it.
static const NSTimeInterval kRestDelay = 0.1;
static const CGFloat kMoveSlop = 10;
// A button stays pressed while the finger is this near its bounds, UIControl's own reach for touch up inside.
static const CGFloat kReach = 70;
// A control up to this wide inside a card or a row is a button of its own (play, ⋯, a heart); the row's own
// control spans the row.
static const CGFloat kSmallControl = 100;
// The glyph sinks this far, the platter grows from this into its size, and a skip's tap nudges this far.
static const CGFloat kGlyphScale = 0.85, kPlatterFrom = 0.8, kNudge = 6;
static const NSTimeInterval kNudgeOut = 0.12;
// The row's wash, inset from the cell's edges so its corners show.
static const CGFloat kRowInsetX = 8, kRowInsetY = 2, kRowRadius = 10;
// SGRTokens.m's press spring (0.32 s, damping 0.62) as Core Animation takes it: stiffness (2 pi / 0.32)^2,
// damping 2 * 0.62 * sqrt(stiffness).
static const CGFloat kSpringStiffness = 385.5, kSpringDamping = 24.35;

static UIColor *platterColor(void) {
    return [UIColor colorWithWhite:1 alpha:SGRIncreaseContrast() ? 0.22 : 0.14];
}

static UIColor *rowWashColor(void) {
    return [UIColor colorWithWhite:1 alpha:SGRIncreaseContrast() ? 0.14 : 0.09];
}

#pragma mark - the watcher

// A recognizer that never recognizes. It sees the touches on its view and ends the press when it fails, which
// any recognizer that takes the touch (a scroll, a swipe, a long press) makes it do.
@interface SGRPressWatcher : UIGestureRecognizer
@property (nonatomic) SGRPressKind kind;
@property (nonatomic, copy) BOOL (^begins)(UITouch *touch);
@property (nonatomic, copy) void (^changed)(BOOL pressed, BOOL tapped);
@end

@implementation SGRPressWatcher {
    __weak UITouch *_touch;
    CGPoint _start;
    BOOL _tracking, _pressed, _inside, _ended;
    NSUInteger _generation;
}

- (instancetype)init {
    if (!(self = [super initWithTarget:nil action:NULL])) return nil;
    self.cancelsTouchesInView = NO;
    self.delaysTouchesBegan = NO;
    self.delaysTouchesEnded = NO;
    return self;
}

- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;
}

- (void)press:(BOOL)pressed tapped:(BOOL)tapped {
    _pressed = pressed;
    if (self.changed) self.changed(pressed, tapped);
}

static UIScrollView *scrollerAbove(UIView *view) {
    for (UIView *v = view.superview; v; v = v.superview) {
        if ([v isKindOfClass:UIScrollView.class]) return (UIScrollView *)v;
    }
    return nil;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_tracking) {
        for (UITouch *touch in touches) [self ignoreTouch:touch forEvent:event];
        return;
    }
    UITouch *touch = touches.anyObject;
    BOOL scrolling = self.kind == SGRPressKindScrolling;
    // A touch that stops a gliding list only stops it.
    if (touches.count > 1 || (scrolling && scrollerAbove(self.view).decelerating) || (self.begins && !self.begins(touch))) {
        self.state = UIGestureRecognizerStateFailed;
        return;
    }
    _touch = touch;
    _tracking = YES;
    _start = [touch locationInView:self.view];
    _inside = YES;
    _ended = NO;
    if (!scrolling) {
        [self press:YES tapped:NO];
        return;
    }
    NSUInteger generation = ++_generation;
    __weak SGRPressWatcher *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRestDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGRPressWatcher *watcher = weakSelf;
        if (!watcher || watcher->_generation != generation || !watcher->_tracking || watcher->_pressed) return;
        if (watcher.state != UIGestureRecognizerStatePossible) return;
        [watcher press:YES tapped:NO];
    });
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = _touch;
    if (!touch || ![touches containsObject:touch]) return;
    CGPoint point = [touch locationInView:self.view];
    if (self.kind == SGRPressKindScrolling) {
        if (hypot(point.x - _start.x, point.y - _start.y) <= kMoveSlop) return;
        _inside = NO;
        self.state = UIGestureRecognizerStateFailed;
        return;
    }
    BOOL inside = CGRectContainsPoint(CGRectInset(self.view.bounds, -kReach, -kReach), point);
    if (inside == _inside) return;
    _inside = inside;
    [self press:inside tapped:NO];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!_touch || ![touches containsObject:_touch]) return;
    _ended = YES;
    self.state = UIGestureRecognizerStateFailed;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.state = UIGestureRecognizerStateFailed;
}

// Once, however the press ends: lifted, taken by another recognizer, cancelled. A recognizer that took the
// touch fails this one while the finger is still down, so the touch's phase says whether it lifted.
- (void)finish {
    if (!_tracking) return;
    UITouch *touch = _touch;
    BOOL tapped = _inside && (_ended || touch.phase == UITouchPhaseEnded);
    _tracking = NO;
    _touch = nil;
    _generation++;
    // A tap quicker than the scrolling delay still shows it was pressed.
    if (tapped && !_pressed) [self press:YES tapped:NO];
    if (_pressed) [self press:NO tapped:tapped];
    _inside = _ended = NO;
}

- (void)setState:(UIGestureRecognizerState)state {
    [super setState:state];
    if (state == UIGestureRecognizerStateFailed || state == UIGestureRecognizerStateCancelled) [self finish];
}

- (void)reset {
    [super reset];
    [self finish];
}

@end

static char kWatcherKey;

void SGRPressWatch(UIView *view, SGRPressKind kind, BOOL (^begins)(UITouch *touch), void (^changed)(BOOL pressed, BOOL tapped)) {
    if (!view) return;
    SGRPressWatcher *watcher = objc_getAssociatedObject(view, &kWatcherKey);
    if (!watcher) {
        watcher = [SGRPressWatcher new];
        objc_setAssociatedObject(view, &kWatcherKey, watcher, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (watcher.view != view) [view addGestureRecognizer:watcher];
    watcher.kind = kind;
    watcher.begins = begins;
    watcher.changed = changed;
}

BOOL SGRPressOnSmallControl(UITouch *touch, UIView *container) {
    for (UIView *v = touch.view; v && v != container; v = v.superview) {
        if ([v isKindOfClass:UIControl.class] && v.bounds.size.width <= kSmallControl) return YES;
    }
    return NO;
}

// A disabled control between the finger and `control` keeps the press from coming.
static BOOL enabledUnder(UITouch *touch, UIView *control) {
    if (!control || control.alpha < 0.01) return NO;
    for (UIView *v = touch.view; v; v = v.superview) {
        if ([v isKindOfClass:UIControl.class] && !((UIControl *)v).enabled) return NO;
        if (v == control) break;
    }
    return YES;
}

void SGRPressAnimateLayer(CALayer *layer, NSString *keyPath, id value, BOOL animated) {
    if (!layer || !keyPath.length || !value) return;
    id from = [(layer.presentationLayer ?: layer) valueForKeyPath:keyPath];
    [layer removeAnimationForKey:keyPath];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [layer setValue:value forKeyPath:keyPath];
    [CATransaction commit];
    if (!animated || SGRReduceMotion() || !from || [from isEqual:value]) return;
    CASpringAnimation *spring = [CASpringAnimation animationWithKeyPath:keyPath];
    spring.mass = 1;
    spring.stiffness = kSpringStiffness;
    spring.damping = kSpringDamping;
    spring.fromValue = from;
    spring.toValue = value;
    spring.duration = spring.settlingDuration;
    [layer addAnimation:spring forKey:keyPath];
}

#pragma mark - a glyph's platter

@interface SGRGlyphPress : NSObject
@property (nonatomic, weak) UIView *glyph, *host;
@property (nonatomic, readonly) UIView *platter;
@property (nonatomic) CGFloat diameter;
@property (nonatomic) SGRPressOptions options;
@property (nonatomic) BOOL down;
@end

@implementation SGRGlyphPress

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _platter = [UIView new];
    _platter.userInteractionEnabled = NO;
    _platter.isAccessibilityElement = NO;
    _platter.accessibilityElementsHidden = YES;
    _platter.alpha = 0;
    _platter.transform = CGAffineTransformMakeScale(kPlatterFrom, kPlatterFrom);
    return self;
}

// Under the glyph's middle, wherever the screen has moved it since the last pass.
- (void)place {
    UIView *glyph = self.glyph, *host = self.host, *platter = self.platter;
    if (!glyph.superview || !host) return;
    if (glyph.superview == host) {
        NSArray<UIView *> *subviews = host.subviews;
        NSUInteger at = [subviews indexOfObject:platter], glyphAt = [subviews indexOfObject:glyph];
        if (at == NSNotFound || at > glyphAt) [host insertSubview:platter belowSubview:glyph];
    } else if (platter.superview != host) {
        [host insertSubview:platter atIndex:0];
    }
    CGPoint center = [host convertPoint:glyph.center fromView:glyph.superview];
    CGFloat diameter = self.diameter;
    [UIView performWithoutAnimation:^{
        platter.bounds = CGRectMake(0, 0, diameter, diameter);
        platter.center = center;
        platter.layer.cornerRadius = diameter / 2;
        platter.backgroundColor = platterColor();
    }];
}

- (void)pressed:(BOOL)pressed tapped:(BOOL)tapped {
    self.down = pressed;
    UIView *glyph = self.glyph, *platter = self.platter;
    BOOL still = SGRReduceMotion();
    if (pressed) [self place];
    SGRAnimate(pressed ? SGRMotionRespond : SGRMotionFade, ^{ platter.alpha = pressed ? 1 : 0; }, nil);
    if (still) {
        platter.transform = CGAffineTransformIdentity;
        return;
    }
    SGRAnimate(SGRMotionPress, ^{
        platter.transform = pressed ? CGAffineTransformIdentity : CGAffineTransformMakeScale(kPlatterFrom, kPlatterFrom);
    }, nil);

    SGRPressOptions options = self.options;
    if (!glyph) return;
    SGRPressOptions nudge = options & (SGRPressNudgeBack | SGRPressNudgeForward);
    if (!pressed && tapped && nudge) {
        CGFloat dx = (nudge & SGRPressNudgeForward) ? kNudge : -kNudge;
        __weak SGRGlyphPress *weakSelf = self;
        [UIView animateWithDuration:kNudgeOut delay:0
            options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
            animations:^{ glyph.transform = CGAffineTransformMakeTranslation(dx, 0); }
            completion:^(BOOL finished) {
                // A new press under way keeps its own sink.
                if (weakSelf.down) return;
                SGRAnimate(SGRMotionPress, ^{ glyph.transform = CGAffineTransformIdentity; }, nil);
            }];
        return;
    }
    if (!(options & SGRPressScale)) return;
    SGRAnimate(SGRMotionPress, ^{
        glyph.transform = pressed ? CGAffineTransformMakeScale(kGlyphScale, kGlyphScale) : CGAffineTransformIdentity;
    }, nil);
}

@end

static char kGlyphPressKey;

void SGRPressGlyph(UIView *control, UIView *glyph, UIView *platterHost, CGFloat diameter, SGRPressOptions options) {
    if (!control || !glyph || !platterHost) return;
    SGRGlyphPress *press = objc_getAssociatedObject(control, &kGlyphPressKey);
    if (!press) {
        press = [SGRGlyphPress new];
        objc_setAssociatedObject(control, &kGlyphPressKey, press, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIView *weakControl = control;
        __weak SGRGlyphPress *weakPress = press;
        SGRPressWatch(control, SGRPressKindButton, ^BOOL(UITouch *touch) {
            return enabledUnder(touch, weakControl);
        }, ^(BOOL pressed, BOOL tapped) {
            [weakPress pressed:pressed tapped:tapped];
        });
        static NSMutableSet<NSString *> *logged;
        if (!logged) logged = [NSMutableSet set];
        NSString *name = NSStringFromClass(control.class);
        if (![logged containsObject:name]) {
            [logged addObject:name];
            SGLog(@"redesign kit: a press platter on %@ (%@)", name, control.accessibilityIdentifier ?: @"no id");
        }
    }
    // A glyph swapped for another goes back to rest first.
    UIView *old = press.glyph;
    if (old && old != glyph && !CGAffineTransformIsIdentity(old.transform)) old.transform = CGAffineTransformIdentity;
    press.glyph = glyph;
    press.host = platterHost;
    press.diameter = diameter;
    press.options = options;
    [press place];
}

#pragma mark - a row's wash

static char kRowWashKey, kRowOnKey;

static void washRow(UIView *cell, BOOL pressed) {
    CALayer *wash = objc_getAssociatedObject(cell, &kRowWashKey);
    if (!wash) return;
    CALayer *drawn = wash.presentationLayer ?: wash;
    float from = drawn.opacity, to = pressed ? 1 : 0;
    [wash removeAnimationForKey:@"opacity"];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    wash.opacity = to;
    [CATransaction commit];
    // On at once, the way a table view highlights; off over a fade.
    if (pressed || from == to) return;
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @(from);
    fade.toValue = @(to);
    fade.duration = SGRCrossfade;
    fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [wash addAnimation:fade forKey:@"opacity"];
}

void SGRPressRow(UIView *cell, BOOL isRow) {
    if (!cell) return;
    CALayer *wash = objc_getAssociatedObject(cell, &kRowWashKey);
    if (!isRow) {
        if (!wash) return;
        objc_setAssociatedObject(cell, &kRowOnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        washRow(cell, NO);
        return;
    }
    if (!wash) {
        wash = [CALayer layer];
        wash.opacity = 0;
        wash.cornerRadius = kRowRadius;
        wash.cornerCurve = kCACornerCurveContinuous;
        objc_setAssociatedObject(cell, &kRowWashKey, wash, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIView *weakCell = cell;
        SGRPressWatch(cell, SGRPressKindScrolling, ^BOOL(UITouch *touch) {
            UIView *row = weakCell;
            return row && objc_getAssociatedObject(row, &kRowOnKey) && !SGRPressOnSmallControl(touch, row);
        }, ^(BOOL pressed, BOOL tapped) {
            washRow(weakCell, pressed);
        });
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"redesign kit: track rows highlight under the finger (%@)", NSStringFromClass(cell.class)); });
    }
    if (!objc_getAssociatedObject(cell, &kRowOnKey)) objc_setAssociatedObject(cell, &kRowOnKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGRect frame = CGRectInset(cell.bounds, kRowInsetX, kRowInsetY);
    CGColorRef color = rowWashColor().CGColor;
    if (wash.superlayer == cell.layer && CGRectEqualToRect(wash.frame, frame) && CGColorEqualToColor(wash.backgroundColor, color)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    // Behind everything the cell draws.
    if (wash.superlayer != cell.layer) [cell.layer insertSublayer:wash atIndex:0];
    wash.frame = frame;
    wash.backgroundColor = color;
    [CATransaction commit];
}
