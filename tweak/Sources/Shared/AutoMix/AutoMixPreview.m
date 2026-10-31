// AutoMixPreview.h says what this is for. The card is static: it is drawn again only when the rows it reads change
// or its width does.
//
// The plot spans kSpanSeconds, long enough for the longest blend with room either side, over a grid of beats at
// kBeatSeconds (120 a minute) with every bar of four drawn brighter. The overlap sits in the middle and is Blend length
// wide, so its width follows the slider. Beat-matched steps the two levels at each beat inside it, every corner
// rounded; Crossfade is one straight fade each way; off, the outgoing curve ends where the incoming one starts, at a
// gray divider in the middle, with no overlap.
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "AutoMixPreview.h"

NSNotificationName const SGAutoMixPlayerOptionsDidChangeNotification = @"SGAutoMixPlayerOptionsDidChangeNotification";

static const double kSpanSeconds = 16, kBeatSeconds = 0.5;
static const NSInteger kBeatsPerBar = 4;
static const CGFloat kCardCorner = 16, kCardPadding = 16, kTextGap = 2, kPlotGap = 12, kPlotHeight = 64;
static const CGFloat kCardTop = 8, kCardBottom = 8, kCurveWidth = 2.5, kDividerWidth = 1.5, kStepCornerRadius = 3;
static const NSTimeInterval kChangeFade = 0.25;

static UIFont *titleFont(void) { return SGCategoryCappedFont(UIFontTextStyleHeadline, UIFontWeightSemibold, UIContentSizeCategoryAccessibilityMedium); }
static UIFont *subtitleFont(void) { return SGCategoryCappedFont(UIFontTextStyleFootnote, UIFontWeightRegular, UIContentSizeCategoryAccessibilityMedium); }

@implementation SGAutoMixPreview {
    SGAutoMixPreviewReading (^_read)(void);
    SGAutoMixPreviewReading _shown;
    BOOL _drawn;
    CGSize _plotSize;   // the plot the curves were made for
    UIView *_card, *_plot;
    UILabel *_title, *_subtitle;
    CAShapeLayer *_grid, *_bars, *_divider, *_outgoing, *_incoming;
}

static CAShapeLayer *curveLayer(NSString *name, UIColor *color, CGFloat width) {
    CAShapeLayer *layer = [CAShapeLayer layer];
    layer.name = name;
    layer.fillColor = nil;
    layer.strokeColor = color.CGColor;
    layer.lineWidth = width;
    layer.lineJoin = kCALineJoinRound;
    layer.lineCap = kCALineCapRound;
    return layer;
}

- (instancetype)initWithReading:(SGAutoMixPreviewReading (^)(void))read {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _read = [read copy];
    _card = [UIView new];
    _card.backgroundColor = SGCardBackground();
    _card.layer.cornerRadius = kCardCorner;
    _card.layer.cornerCurve = kCACornerCurveContinuous;
    [self addSubview:_card];
    _title = [UILabel new];
    _title.textColor = UIColor.whiteColor;
    _title.numberOfLines = 0;
    _subtitle = [UILabel new];
    _subtitle.textColor = SGGrey();
    _subtitle.numberOfLines = 0;
    _plot = [UIView new];
    _grid = curveLayer(@"grid", [UIColor colorWithWhite:1 alpha:0.1], 1);
    _bars = curveLayer(@"bars", [UIColor colorWithWhite:1 alpha:0.22], 1);
    _divider = curveLayer(@"divider", SGGrey(), kDividerWidth);
    _outgoing = curveLayer(@"outgoing", [UIColor colorWithWhite:1 alpha:0.9], kCurveWidth);
    _incoming = curveLayer(@"incoming", SGAccentMark(), kCurveWidth);
    for (CAShapeLayer *layer in @[_grid, _bars, _divider, _outgoing, _incoming]) [_plot.layer addSublayer:layer];
    for (UIView *view in @[_title, _subtitle, _plot]) [_card addSubview:view];
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitStaticText;
    [self reload];
    return self;
}

#pragma mark - what it says

static NSString *titleFor(SGAutoMixPreviewReading reading) {
    switch (reading.style) {
        case SGAutoMixPreviewOff: return SGL(@"settings.automix.preview.off.title", @"Every song plays to its end");
        case SGAutoMixPreviewBeatMatched: return SGL(@"settings.automix.preview.beatmatched.title", @"Beat-matched mix");
        case SGAutoMixPreviewCrossfade:
            return [NSString stringWithFormat:SGL(@"settings.automix.preview.crossfade.title", @"%ld s crossfade"), (long)reading.seconds];
    }
}

static NSString *subtitleFor(SGAutoMixPreviewReading reading) {
    switch (reading.style) {
        case SGAutoMixPreviewOff: return SGL(@"settings.automix.preview.off.subtitle", @"AutoMix is off");
        case SGAutoMixPreviewBeatMatched:
            return [NSString stringWithFormat:SGL(@"settings.automix.preview.beatmatched.subtitle", @"%ld s blend, on the beat"), (long)reading.seconds];
        case SGAutoMixPreviewCrossfade: return SGL(@"settings.automix.preview.crossfade.subtitle", @"A plain fade, the same length both ways");
    }
}

- (void)reload {
    SGAutoMixPreviewReading reading = _read();
    if (_drawn && reading.style == _shown.style && reading.seconds == _shown.seconds) return;
    BOOL animated = _drawn && self.window && !UIAccessibilityIsReduceMotionEnabled();
    _shown = reading;
    _drawn = YES;
    _plotSize = CGSizeZero;   // the curves are made again at the next layout
    if (animated) {
        CATransition *fade = [CATransition animation];
        fade.type = kCATransitionFade;
        fade.duration = kChangeFade;
        [_card.layer addAnimation:fade forKey:@"change"];
    }
    _title.text = titleFor(reading);
    _subtitle.text = subtitleFor(reading);
    self.accessibilityLabel = [NSString stringWithFormat:SGL(@"settings.automix.preview.accessibility", @"AutoMix, %@, %@"), _title.text, _subtitle.text];
    [self setNeedsLayout];
    if (!animated) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [self layoutIfNeeded];
        [CATransaction commit];
    }
}

#pragma mark - layout

- (CGFloat)textHeightForWidth:(CGFloat)width {
    _title.font = titleFont();
    _subtitle.font = subtitleFont();
    return ceil([_title sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height) + kTextGap
         + ceil([_subtitle sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height);
}

- (CGFloat)heightForWidth:(CGFloat)width {
    CGFloat inner = width - self.layoutMargins.left - self.layoutMargins.right - 2 * kCardPadding;
    return kCardTop + kCardPadding + [self textHeightForWidth:inner] + kPlotGap + kPlotHeight + kCardPadding + kCardBottom;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect card = CGRectMake(self.layoutMargins.left, kCardTop, self.bounds.size.width - self.layoutMargins.left - self.layoutMargins.right,
                             self.bounds.size.height - kCardTop - kCardBottom);
    _card.frame = card;
    CGFloat inner = card.size.width - 2 * kCardPadding;
    CGFloat titleHeight = ceil([_title sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)].height);
    CGFloat subtitleHeight = ceil([_subtitle sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)].height);
    _title.frame = CGRectMake(kCardPadding, kCardPadding, inner, titleHeight);
    _subtitle.frame = CGRectMake(kCardPadding, CGRectGetMaxY(_title.frame) + kTextGap, inner, subtitleHeight);
    _plot.frame = CGRectMake(kCardPadding, CGRectGetMaxY(_subtitle.frame) + kPlotGap, inner, kPlotHeight);
    if (CGSizeEqualToSize(_plot.bounds.size, _plotSize)) return;
    _plotSize = _plot.bounds.size;
    [self drawCurves];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (previous.preferredContentSizeCategory != self.traitCollection.preferredContentSizeCategory) {
        _title.font = titleFont();
        _subtitle.font = subtitleFont();
        [self setNeedsLayout];
    }
}

#pragma mark - the curves

// Straight through `points`, each corner between rounded by up to `radius` (0 for none) and at most half the shorter
// of its two sides.
static UIBezierPath *pathThrough(NSArray<NSValue *> *points, CGFloat radius) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:points.firstObject.CGPointValue];
    for (NSUInteger i = 1; i + 1 < points.count; i++) {
        CGPoint before = points[i - 1].CGPointValue, corner = points[i].CGPointValue, after = points[i + 1].CGPointValue;
        CGFloat into = hypot(corner.x - before.x, corner.y - before.y), out = hypot(after.x - corner.x, after.y - corner.y);
        CGFloat r = MIN(radius, MIN(into, out) / 2);
        if (r <= 0) {
            [path addLineToPoint:corner];
            continue;
        }
        [path addLineToPoint:CGPointMake(corner.x - (corner.x - before.x) / into * r, corner.y - (corner.y - before.y) / into * r)];
        [path addQuadCurveToPoint:CGPointMake(corner.x + (after.x - corner.x) / out * r, corner.y + (after.y - corner.y) / out * r) controlPoint:corner];
    }
    if (points.count > 1) [path addLineToPoint:points.lastObject.CGPointValue];
    return path;
}

- (void)drawCurves {
    CGFloat width = _plotSize.width, height = _plotSize.height, inset = kCurveWidth;
    if (width <= 0) return;
    CGFloat (^x)(double) = ^CGFloat(double seconds) { return width * seconds / kSpanSeconds; };
    CGFloat (^y)(double) = ^CGFloat(double level) { return inset + (1 - level) * (height - 2 * inset); };

    UIBezierPath *grid = [UIBezierPath bezierPath], *bars = [UIBezierPath bezierPath];
    NSInteger beats = (NSInteger)llround(kSpanSeconds / kBeatSeconds);
    for (NSInteger beat = 1; beat < beats; beat++) {
        UIBezierPath *path = beat % kBeatsPerBar ? grid : bars;
        [path moveToPoint:CGPointMake(x(beat * kBeatSeconds), 0)];
        [path addLineToPoint:CGPointMake(x(beat * kBeatSeconds), height)];
    }
    _grid.path = grid.CGPath;
    _bars.path = bars.CGPath;

    BOOL off = _shown.style == SGAutoMixPreviewOff;
    double middle = kSpanSeconds / 2, length = off ? 0 : _shown.seconds;
    double start = middle - length / 2, end = middle + length / 2;
    NSValue *(^at)(double, double) = ^NSValue *(double seconds, double level) { return [NSValue valueWithCGPoint:CGPointMake(x(seconds), y(level))]; };
    NSMutableArray<NSValue *> *outgoing = [NSMutableArray arrayWithObjects:at(0, 1), at(start, 1), nil];
    NSMutableArray<NSValue *> *incoming = [NSMutableArray arrayWithObject:at(start, off ? 1 : 0)];
    switch (_shown.style) {
        case SGAutoMixPreviewOff: break;
        case SGAutoMixPreviewBeatMatched: {
            // Each beat holds a level and the next beat steps to the next one, an equal-power blend.
            NSInteger steps = (NSInteger)llround(length / kBeatSeconds);
            double fallen = 1, risen = 0;
            for (NSInteger step = 1; step <= steps; step++) {
                double beat = start + step * kBeatSeconds, share = (double)step / steps;
                [outgoing addObject:at(beat, fallen)];
                [incoming addObject:at(beat, risen)];
                fallen = cos(M_PI_2 * share);
                risen = sin(M_PI_2 * share);
                [outgoing addObject:at(beat, fallen)];
                [incoming addObject:at(beat, risen)];
            }
            break;
        }
        case SGAutoMixPreviewCrossfade:
            [outgoing addObject:at(end, 0)];
            [incoming addObject:at(end, 1)];
            break;
    }
    [incoming addObject:at(kSpanSeconds, 1)];
    CGFloat radius = _shown.style == SGAutoMixPreviewBeatMatched ? kStepCornerRadius : 0;
    _outgoing.path = pathThrough(outgoing, radius).CGPath;
    _incoming.path = pathThrough(incoming, radius).CGPath;
    UIBezierPath *divider = [UIBezierPath bezierPath];
    if (off) {
        [divider moveToPoint:CGPointMake(x(middle), 0)];
        [divider addLineToPoint:CGPointMake(x(middle), height)];
    }
    _divider.path = divider.CGPath;
    _plot.alpha = off ? 0.6 : 1;
}

@end
