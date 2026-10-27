// Rolling time digits (SGRRefinements.h): a label's changed characters roll up into place as Spotify sets its text.
//
// The label keeps drawing Spotify's text, the new one already, its accessibility untouched. For the animation's
// length a mask on the label's layer takes the changed characters' columns out of it, and a view laid over the
// label, clipped to it and hidden from accessibility, carries the old characters up and out and the new ones up
// and in, each a label of its own placed where Core Text laid the character's glyphs. Under Reduce Motion they
// crossfade in place. A text with a run laid out right to left shows its change at once. Nothing runs between
// Spotify's changes: no timer, no display link.
//
// Threading: main thread only.
#import <objc/runtime.h>
#import <CoreText/CoreText.h>
#import "SGRRefinements.h"
#import "SGRRestyle.h"
#import "SGRTokens.h"

static const NSTimeInterval kRollDuration = 0.25;
// Room past a character's own advance its stand-in may draw in, so a glyph overhanging it is not cut off.
static const CGFloat kGlyphSlack = 2;

static char kStateKey;

@interface SGRDigitsState : NSObject
// The window the label was in at its last change; nil once it moved to another or out of one.
@property (nonatomic, weak) UIWindow *window;
@property (nonatomic) CFTimeInterval changedAt;   // 0 until the first change
@property (nonatomic, strong) UIView *overlay;
@property (nonatomic, strong) CAShapeLayer *mask;
@end

@implementation SGRDigitsState
@end

BOOL SGRRollingDigitsWatched(UILabel *label) {
    return objc_getAssociatedObject(label, &kStateKey) != nil;
}

void SGRRollDigits(UILabel *label) {
    if (![label isKindOfClass:UILabel.class]) return;
    if (!SGRRollingDigitsWatched(label)) {
        SGRDigitsState *state = [SGRDigitsState new];
        state.window = label.window;
        objc_setAssociatedObject(label, &kStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    SGRMonospacedDigits(label);
}

// The overlay and the mask taken away, a running animation's included.
static void finish(UILabel *label, SGRDigitsState *state) {
    [state.overlay removeFromSuperview];
    state.overlay = nil;
    if (state.mask && label.layer.mask == state.mask) label.layer.mask = nil;
    state.mask = nil;
}

void SGRRollingDigitsMovedToWindow(UILabel *label) {
    SGRDigitsState *state = objc_getAssociatedObject(label, &kStateKey);
    finish(label, state);
    state.window = nil;
}

// The text with the label's font wherever it has none, so Core Text measures what the label draws.
static NSAttributedString *measured(NSAttributedString *text, UIFont *font) {
    NSMutableAttributedString *copy = [text mutableCopy];
    [text enumerateAttribute:NSFontAttributeName inRange:NSMakeRange(0, text.length) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
        if (!value && font) [copy addAttribute:NSFontAttributeName value:font range:range];
    }];
    return copy;
}

// Where one character's glyphs sit across the label, left edge to right edge.
typedef struct {
    CGFloat left, right;
} SGRColumn;

// Each character of `text` as the label lays it out, from the glyph runs Core Text made of it: every glyph's
// position and advance, mapped back to its character by the run's string indices. nil when the text cannot roll by
// columns: a run laid out right to left or out of string order (a right-to-left or mixed text), or a character
// without a glyph of its own.
static NSData *columnsOf(UILabel *label, NSAttributedString *text) {
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)measured(text, label.font));
    CGFloat width = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
    NSTextAlignment alignment = label.textAlignment;
    if (alignment == NSTextAlignmentNatural) {
        BOOL rtl = label.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
        alignment = rtl ? NSTextAlignmentRight : NSTextAlignmentLeft;
    }
    CGFloat room = label.bounds.size.width - width;
    CGFloat origin = alignment == NSTextAlignmentRight ? room : alignment == NSTextAlignmentCenter ? room / 2 : 0;
    NSUInteger length = text.length;
    NSMutableData *data = [NSMutableData dataWithLength:length * sizeof(SGRColumn)];
    SGRColumn *columns = data.mutableBytes;
    for (NSUInteger i = 0; i < length; i++) columns[i] = (SGRColumn){NAN, NAN};
    BOOL readable = YES;
    for (id item in (__bridge NSArray *)CTLineGetGlyphRuns(line)) {
        CTRunRef run = (__bridge CTRunRef)item;
        if (CTRunGetStatus(run) & (kCTRunStatusRightToLeft | kCTRunStatusNonMonotonic)) {
            readable = NO;
            break;
        }
        CFIndex count = CTRunGetGlyphCount(run);
        NSMutableData *positions = [NSMutableData dataWithLength:count * sizeof(CGPoint)];
        NSMutableData *advances = [NSMutableData dataWithLength:count * sizeof(CGSize)];
        NSMutableData *indices = [NSMutableData dataWithLength:count * sizeof(CFIndex)];
        CTRunGetPositions(run, CFRangeMake(0, 0), positions.mutableBytes);
        CTRunGetAdvances(run, CFRangeMake(0, 0), advances.mutableBytes);
        CTRunGetStringIndices(run, CFRangeMake(0, 0), indices.mutableBytes);
        const CGPoint *position = positions.bytes;
        const CGSize *advance = advances.bytes;
        const CFIndex *index = indices.bytes;
        for (CFIndex g = 0; g < count; g++) {
            CGFloat left = origin + position[g].x, right = left + advance[g].width;
            SGRColumn *column = &columns[index[g]];
            column->left = isnan(column->left) ? left : MIN(column->left, left);
            column->right = isnan(column->right) ? right : MAX(column->right, right);
        }
    }
    CFRelease(line);
    for (NSUInteger i = 0; readable && i < length; i++) {
        if (isnan(columns[i].left)) readable = NO;
    }
    return readable ? data : nil;
}

// One character of `text` as the label draws it, at its place in the line.
static UILabel *glyphOf(UILabel *label, NSAttributedString *text, NSUInteger index, SGRColumn column) {
    UILabel *glyph = [UILabel new];
    glyph.font = label.font;
    glyph.textColor = label.textColor;
    glyph.attributedText = [text attributedSubstringFromRange:NSMakeRange(index, 1)];
    glyph.textAlignment = NSTextAlignmentLeft;
    glyph.lineBreakMode = NSLineBreakByClipping;
    glyph.frame = CGRectMake(column.left, 0, column.right - column.left + kGlyphSlack, label.bounds.size.height);
    return glyph;
}

// The indexes of `text` that are `rolled`, or all of them.
static NSIndexSet *leaving(NSAttributedString *before, NSAttributedString *after, NSIndexSet *rolled) {
    return before.length == after.length ? rolled : [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, before.length)];
}

static void animate(UILabel *label, SGRDigitsState *state, NSAttributedString *before, SGRDigitsChange change) {
    UIView *host = label.superview;
    NSAttributedString *after = label.attributedText;
    if (!host || !after.length || CGRectIsEmpty(label.bounds)) return;
    NSData *newColumnData = columnsOf(label, after), *oldColumnData = columnsOf(label, before);
    // Right to left or mixed: shown at once.
    if (!newColumnData || !oldColumnData) return;
    const SGRColumn *newColumns = newColumnData.bytes, *oldColumns = oldColumnData.bytes;
    NSIndexSet *rolled = SGRDigitsRolled(before.string, after.string);

    UIView *overlay = [[UIView alloc] initWithFrame:[label convertRect:label.bounds toView:host]];
    overlay.clipsToBounds = YES;
    overlay.userInteractionEnabled = NO;
    overlay.isAccessibilityElement = NO;
    overlay.accessibilityElementsHidden = YES;
    CGFloat travel = change == SGRDigitsChangeRoll ? label.bounds.size.height : 0;

    // The label without the changed characters' columns: the box around it, each column cut out of it.
    CGRect bounds = label.bounds;
    CGFloat outset = bounds.size.height;
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:CGRectInset(bounds, -outset, -outset)];
    NSMutableArray<UILabel *> *incoming = [NSMutableArray array], *outgoing = [NSMutableArray array];
    [rolled enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        SGRColumn column = newColumns[i];
        [path appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(column.left, -outset, column.right - column.left, bounds.size.height + 2 * outset)]];
        UILabel *glyph = glyphOf(label, after, i, column);
        glyph.transform = CGAffineTransformMakeTranslation(0, travel);
        glyph.alpha = 0;
        [overlay addSubview:glyph];
        [incoming addObject:glyph];
    }];
    [leaving(before, after, rolled) enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        UILabel *glyph = glyphOf(label, before, i, oldColumns[i]);
        [overlay addSubview:glyph];
        [outgoing addObject:glyph];
    }];
    CAShapeLayer *mask = [CAShapeLayer layer];
    mask.frame = bounds;
    mask.fillRule = kCAFillRuleEvenOdd;
    mask.path = path.CGPath;

    [host insertSubview:overlay aboveSubview:label];
    label.layer.mask = mask;
    state.overlay = overlay;
    state.mask = mask;
    void (^moves)(void) = ^{
        for (UILabel *glyph in incoming) {
            glyph.transform = CGAffineTransformIdentity;
            glyph.alpha = 1;
        }
        for (UILabel *glyph in outgoing) {
            glyph.transform = CGAffineTransformMakeTranslation(0, -travel);
            glyph.alpha = 0;
        }
    };
    void (^done)(BOOL) = ^(BOOL finished) {
        if (state.overlay == overlay) finish(label, state);
    };
    if (change == SGRDigitsChangeRoll) {
        [UIView animateWithDuration:kRollDuration delay:0 options:UIViewAnimationOptionCurveEaseOut animations:moves completion:done];
    } else {
        SGRAnimate(SGRMotionFade, moves, done);
    }
}

void SGRRollingDigitsTextChanged(UILabel *label, NSAttributedString *before) {
    SGRDigitsState *state = objc_getAssociatedObject(label, &kStateKey);
    if (!state) return;
    NSString *after = label.text ?: @"";
    UIWindow *window = label.window;
    CFTimeInterval now = CACurrentMediaTime();
    BOOL attached = window && state.window == window;
    NSTimeInterval since = state.changedAt > 0 ? now - state.changedAt : -1;
    SGRDigitsChange change = SGRDigitsChangeFor(before.string ?: @"", after, attached, since, SGRReduceMotion());
    if (change == SGRDigitsChangeNone) return;
    state.changedAt = now;
    state.window = window;
    finish(label, state);
    if (change != SGRDigitsChangeJump) animate(label, state, before, change);
}
