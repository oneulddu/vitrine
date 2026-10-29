// The Visualizer's two lyric styles after Lyrics, over the quiet hills PlayerVisualiser.m draws for all three:
//
// Poster sets the sung line as a type poster: large and heavy, left-aligned within the player's margins, wrapped
// and shrunk until it fits half the field's height, over a halftone print of the cover (a grid of dots each as
// large as its cell of the cover is bright, in the cover's own colors) laid on black at the Print strength. Each
// word takes the type color as its start passes; the words still ahead stay at the Words ahead opacity. A new
// line fades over the old one, rising a little unless Reduce Motion is on.
//
// Cut shows the line one word at a time, as large as one line of the field's width allows, over the cover
// darkened by Background and a few flat blocks of the cover's flow colors, placed and sized from the line and
// word, never at random. Each new word jumps the word and the blocks a little, by Motion, and settles; Reduce
// Motion keeps them still. Whole line puts the line itself, small, under the word.
//
// Cost: no Metal, layers and labels only. The halftone is made once per artwork off the main queue and kept for
// that artwork; text is built and measured only when the line or the word changes. On the frame clock a stage
// only counts the started words of the line it is handed and compares two values.
//
// Threading: main thread only, but for the halftone's drawing.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Settings/SGModPage.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Player.h"
#import "PlayerLyricStages.h"

#pragma mark - the parameters

NSNotificationName const SGRVisualiserParamsDidChangeNotification = @"spotifyglass.visualizer.paramsDidChange";

typedef NS_ENUM(NSUInteger, SGRParamKind) { SGRParamNumber, SGRParamSwitch, SGRParamColour };

typedef struct {
    __unsafe_unretained NSString *style, *param;
    SGRParamKind kind;
    double least, most, step, fallback;
} SGRParamSpec;

static const SGRParamSpec kParams[] = {
    {SGRVisualiserPosterID, SGRVisualiserHalftone, SGRParamSwitch, 0, 1, 1, 1},
    {SGRVisualiserPosterID, SGRVisualiserInk, SGRParamColour, 0, 0xFFFFFF, 1, 0xF4EFE6},
    {SGRVisualiserPosterID, SGRVisualiserBackdrop, SGRParamNumber, 0, 1, 0.05, 0.6},
    {SGRVisualiserPosterID, SGRVisualiserGhost, SGRParamNumber, 0, 0.5, 0.01, 0.35},
    {SGRVisualiserCutID, SGRVisualiserInk, SGRParamColour, 0, 0xFFFFFF, 1, 0xFFFFFF},
    {SGRVisualiserCutID, SGRVisualiserShade, SGRParamNumber, 0, 1, 0.05, 0.75},
    {SGRVisualiserCutID, SGRVisualiserMotion, SGRParamNumber, 0, 1.5, 0.05, 1},
    {SGRVisualiserCutID, SGRVisualiserSubtitle, SGRParamSwitch, 0, 1, 1, 1},
};

static const SGRParamSpec *specOf(NSString *style, NSString *param) {
    for (size_t i = 0; i < sizeof kParams / sizeof kParams[0]; i++) {
        if ([kParams[i].style isEqualToString:style] && [kParams[i].param isEqualToString:param]) return &kParams[i];
    }
    return NULL;
}

SGRVisualiserParamLimits SGRVisualiserParamLimitsOf(NSString *style, NSString *param) {
    const SGRParamSpec *spec = specOf(style, param);
    return spec ? (SGRVisualiserParamLimits){spec->least, spec->most, spec->step} : (SGRVisualiserParamLimits){0, 0, 0};
}

// "#RRGGBB" as 0xRRGGBB, -1 for anything else.
static NSInteger parseHex(NSString *text) {
    if (text.length != 7 || [text characterAtIndex:0] != '#') return -1;
    NSInteger rgb = 0;
    for (NSUInteger i = 1; i < 7; i++) {
        unichar c = [text characterAtIndex:i];
        NSInteger digit = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
        if (digit < 0) return -1;
        rgb = rgb * 16 + digit;
    }
    return rgb;
}

double SGRVisualiserParam(NSString *style, NSString *param) {
    const SGRParamSpec *spec = specOf(style, param);
    if (!spec) return 0;
    id all = [NSUserDefaults.standardUserDefaults objectForKey:SGRKeyVisualiserParams];
    id own = [all isKindOfClass:NSDictionary.class] ? all[style] : nil;
    id value = [own isKindOfClass:NSDictionary.class] ? own[param] : nil;
    switch (spec->kind) {
        case SGRParamNumber: {
            double number = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : NAN;
            return isfinite(number) ? MIN(spec->most, MAX(spec->least, number)) : spec->fallback;
        }
        case SGRParamSwitch:
            return [value isKindOfClass:NSNumber.class] ? ([value boolValue] ? 1 : 0) : spec->fallback;
        case SGRParamColour: {
            NSInteger rgb = [value isKindOfClass:NSString.class] ? parseHex(value) : -1;
            return rgb >= 0 ? rgb : spec->fallback;
        }
    }
    return spec->fallback;
}

void SGRSetVisualiserParam(NSString *style, NSString *param, double value) {
    const SGRParamSpec *spec = specOf(style, param);
    if (!spec || !isfinite(value)) return;
    id stored = nil;
    switch (spec->kind) {
        case SGRParamNumber: {
            // Every step is a whole fraction (1/20, 1/100), so a whole number of steps divided out lands on the
            // double nearest the decimal, the same one its default is written as.
            double steps = round(1 / spec->step);
            double number = MIN(spec->most, MAX(spec->least, round(value * steps) / steps));
            if (number != spec->fallback) stored = @(number);
            break;
        }
        case SGRParamSwitch:
            if ((value != 0) != (spec->fallback != 0)) stored = @(value != 0);
            break;
        case SGRParamColour: {
            NSInteger rgb = lround(value) & 0xFFFFFF;
            if (rgb != lround(spec->fallback)) stored = [NSString stringWithFormat:@"#%06lX", (long)rgb];
            break;
        }
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id all = [defaults objectForKey:SGRKeyVisualiserParams];
    NSMutableDictionary *styles = [all isKindOfClass:NSDictionary.class] ? [all mutableCopy] : [NSMutableDictionary dictionary];
    id own = styles[style];
    NSMutableDictionary *params = [own isKindOfClass:NSDictionary.class] ? [own mutableCopy] : [NSMutableDictionary dictionary];
    params[param] = stored;
    styles[style] = params.count ? params : nil;
    if (styles.count) [defaults setObject:styles forKey:SGRKeyVisualiserParams];
    else [defaults removeObjectForKey:SGRKeyVisualiserParams];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRVisualiserParamsDidChangeNotification object:nil];
}

#pragma mark - the halftone

// The print: kDots dots across and down, each in a cell of kDotCell pixels, at most kDotLargest of the cell across.
enum { kDots = 64, kDotCell = 16 };
static const CGFloat kDotLargest = 1;

// The cover as a halftone print on black: each cell of the cover a dot of its average color, its area the
// cell's brightness. Any thread.
static CGImageRef halftone(CGImageRef cover) {
    if (!cover) return NULL;
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    uint8_t grid[kDots * kDots * 4];
    CGContextRef small = CGBitmapContextCreate(grid, kDots, kDots, 8, kDots * 4, space, (CGBitmapInfo)kCGImageAlphaNoneSkipLast);
    CGContextSetInterpolationQuality(small, kCGInterpolationHigh);
    CGContextDrawImage(small, CGRectMake(0, 0, kDots, kDots), cover);
    CGContextRelease(small);
    const size_t side = kDots * kDotCell;
    CGContextRef print = CGBitmapContextCreate(NULL, side, side, 8, 0, space, (CGBitmapInfo)kCGImageAlphaNoneSkipLast);
    CGColorSpaceRelease(space);
    if (!print) return NULL;
    CGContextSetRGBFillColor(print, 0, 0, 0, 1);
    CGContextFillRect(print, CGRectMake(0, 0, side, side));
    for (int row = 0; row < kDots; row++) {
        for (int column = 0; column < kDots; column++) {
            const uint8_t *pixel = grid + (row * kDots + column) * 4;
            CGFloat r = pixel[0] / 255.0, g = pixel[1] / 255.0, b = pixel[2] / 255.0;
            CGFloat radius = kDotCell * kDotLargest / 2 * sqrt(0.2126 * r + 0.7152 * g + 0.0722 * b);
            if (radius < 0.5) continue;
            // The grid's first row is the cover's top; the print's origin is its foot.
            CGFloat x = (column + 0.5) * kDotCell, y = side - (row + 0.5) * kDotCell;
            CGContextSetRGBFillColor(print, r, g, b, 1);
            CGContextFillEllipseInRect(print, CGRectMake(x - radius, y - radius, 2 * radius, 2 * radius));
        }
    }
    CGImageRef image = CGBitmapContextCreateImage(print);
    CGContextRelease(print);
    return image;
}

// The newest artwork's print, kept for it (nil when it could not be made, which is as final as a print), the job
// it came from, the last job begun, and the callers waiting on a print being made, by artwork identity. Jobs are
// numbered as they begin, so one that ends after a newer one has been kept hands its print to its own callers
// only.
static NSString *sg_printFor;
static id sg_print;
static NSUInteger sg_printKept, sg_printBegun;
static NSMutableDictionary<NSString *, NSMutableArray *> *sg_printWaiting;

// Hands `done` the print of `cover`, nil when it could not be made, on main: at once when it is the kept one, else
// once it is made.
static void printFor(UIImage *cover, NSString *identity, void (^done)(id print)) {
    if ([identity isEqualToString:sg_printFor]) {
        done(sg_print);
        return;
    }
    if (!sg_printWaiting) sg_printWaiting = [NSMutableDictionary dictionary];
    NSMutableArray *waiting = sg_printWaiting[identity];
    if (waiting) {
        [waiting addObject:[done copy]];
        return;
    }
    sg_printWaiting[identity] = [NSMutableArray arrayWithObject:[done copy]];
    NSUInteger job = ++sg_printBegun;
    CGImageRef source = CGImageRetain(cover.CGImage);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        id made = CFBridgingRelease(halftone(source));
        CGImageRelease(source);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (job > sg_printKept) {
                sg_printKept = job;
                sg_printFor = identity;
                sg_print = made;
            }
            NSArray *calls = sg_printWaiting[identity];
            [sg_printWaiting removeObjectForKey:identity];
            for (void (^call)(id) in calls) call(made);
        });
    });
}

#pragma mark - the stage

// The index of the last word of `line` whose start has passed at `ms`, -1 before the first. Allocates nothing.
static NSInteger startedWord(SGKaraokeLine *line, NSInteger ms) {
    NSInteger started = -1, index = 0;
    for (SGKaraokeWord *word in line.words) {
        if (word.start > ms) break;
        started = index++;
    }
    return started;
}

static NSString *trimmed(NSString *text) {
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

@interface SGRLyricStage ()
@property (nonatomic, readonly) CGRect field;
@property (nonatomic, readonly) CGFloat centre;
@property (nonatomic, readonly) SGKaraokeLine *line;   // nil while none shows
@property (nonatomic, readonly) NSInteger word;        // the last started word of the line, -1 before the first
@end

@interface SGRPosterStage : SGRLyricStage
@end

@interface SGRCutStage : SGRLyricStage
@end

@implementation SGRLyricStage {
    BOOL _shown;
}

+ (SGRLyricStage *)stageForStyle:(NSString *)identifier {
    if ([identifier isEqualToString:SGRVisualiserPosterID]) return [[SGRPosterStage alloc] initWithFrame:CGRectZero];
    if ([identifier isEqualToString:SGRVisualiserCutID]) return [[SGRCutStage alloc] initWithFrame:CGRectZero];
    return nil;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    self.clipsToBounds = YES;
    self.alpha = 0;
    _word = -1;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(takeParams) name:SGRVisualiserParamsDidChangeNotification object:nil];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)setField:(CGRect)field centre:(CGFloat)centre {
    if (CGRectEqualToRect(field, _field) && centre == _centre) return;
    _field = field;
    _centre = centre;
    [self layOutType];
}

- (void)showLine:(NSInteger)index of:(NSArray<SGKaraokeLine *> *)lines at:(NSInteger)ms {
    SGKaraokeLine *line = index >= 0 && index < (NSInteger)lines.count ? lines[(NSUInteger)index] : nil;
    NSInteger word = line ? startedWord(line, ms) : -1;
    if (line == _line && word == _word) return;
    BOOL newLine = line != _line;
    _line = line;
    _word = word;
    if (line && newLine) [self takeLine];
    else if (line) [self takeWord];
    if (_shown == (line != nil)) return;
    _shown = line != nil;
    CGFloat alpha = _shown ? 1 : 0;
    SGRAnimate(SGRMotionFade, ^{ self.alpha = alpha; }, nil);
}

// The style's own: the parameters read again, the cover, the colors, a new line (at its started word) and a new
// word of the same line.
- (void)takeParams {}
- (void)setCover:(UIImage *)cover identity:(NSString *)identity {}
- (void)setColours:(NSArray<UIColor *> *)colours {}
- (void)takeLine {}
- (void)takeWord {}
// The field moved: the line shown is laid out again where it is, without motion.
- (void)layOutType {}

@end

#pragma mark - Poster

// The type: heavy, from kPosterLargest points down by kPosterShrink until the line fits kPosterHeight of the
// field's height, never under kPosterSmallest. A new line rises kPosterRise points and grows from kPosterScale.
static const CGFloat kPosterLargest = 72, kPosterSmallest = 24, kPosterShrink = 0.92, kPosterHeight = 0.5;
static const CGFloat kPosterRise = 18, kPosterScale = 0.97;

static UIFont *posterFont(CGFloat size) {
    return [UIFont systemFontOfSize:size weight:UIFontWeightHeavy];
}

@implementation SGRPosterStage {
    CALayer *_print;   // the cover's print, or the cover itself with Halftone off, on the stage's black
    NSArray<UILabel *> *_labels;
    UILabel *_front;
    UIImage *_cover;
    NSString *_coverID;
    id _halftone;
    // The print was asked for this artwork, and the answer came: the print, or nil when it could not be made.
    BOOL _printAsked, _printAnswered;
    BOOL _halftoneOn;
    UIColor *_ink, *_ahead;
    // The line as set: its text, each word's range in it, and the attributes it is set in.
    NSString *_text;
    NSArray<NSValue *> *_ranges;
    NSDictionary *_attributes;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = UIColor.blackColor;
    _print = [CALayer layer];
    _print.contentsGravity = kCAGravityResizeAspectFill;
    _print.masksToBounds = YES;
    [self.layer addSublayer:_print];
    NSMutableArray *labels = [NSMutableArray array];
    for (int i = 0; i < 2; i++) {
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.numberOfLines = 0;
        label.alpha = 0;
        [self addSubview:label];
        [labels addObject:label];
    }
    _labels = labels;
    _front = labels.firstObject;
    [self takeParams];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _print.frame = self.bounds;
    [CATransaction commit];
}

- (void)takeParams {
    _halftoneOn = SGRVisualiserParam(SGRVisualiserPosterID, SGRVisualiserHalftone) != 0;
    UIColor *ink = SGColorRGB(lround(SGRVisualiserParam(SGRVisualiserPosterID, SGRVisualiserInk)));
    _ink = ink;
    _ahead = [ink colorWithAlphaComponent:SGRVisualiserParam(SGRVisualiserPosterID, SGRVisualiserGhost)];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _print.opacity = (float)SGRVisualiserParam(SGRVisualiserPosterID, SGRVisualiserBackdrop);
    [CATransaction commit];
    [self showCover];
    if (self.line) [self paint];
}

- (void)setCover:(UIImage *)cover identity:(NSString *)identity {
    if (identity == _coverID || [identity isEqualToString:_coverID]) return;
    _cover = identity ? cover : nil;
    _coverID = _cover ? [identity copy] : nil;
    _halftone = nil;
    _printAsked = _printAnswered = NO;
    [self showCover];
}

// The print with Halftone on, asked for once for this artwork, black until it comes; the cover with it off, and for
// an artwork whose print could not be made.
- (void)showCover {
    if (_halftoneOn && _cover && !_printAsked) {
        _printAsked = YES;
        NSString *identity = _coverID;
        __weak SGRPosterStage *weakSelf = self;
        printFor(_cover, identity, ^(id print) {
            SGRPosterStage *stage = weakSelf;
            if (!stage || ![identity isEqualToString:stage->_coverID]) return;
            stage->_halftone = print;
            stage->_printAnswered = YES;
            [stage showCover];
        });
    }
    BOOL plain = !_halftoneOn || (_printAnswered && !_halftone);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _print.contents = plain ? (id)_cover.CGImage : _halftone;
    [CATransaction commit];
}

// The new line set in the label behind, painted to its started word, which fades over the one in front.
- (void)takeLine {
    NSMutableString *text = [NSMutableString string];
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    for (SGKaraokeWord *word in self.line.words) {
        if (text.length && !word.joined) [text appendString:@" "];
        NSUInteger at = text.length;
        [text appendString:word.text ?: @""];
        [ranges addObject:[NSValue valueWithRange:NSMakeRange(at, text.length - at)]];
    }
    _text = text;
    _ranges = ranges;
    UILabel *old = _front;
    UILabel *next = _labels.firstObject == old ? _labels.lastObject : _labels.firstObject;
    BOOL still = SGRReduceMotion();
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _front = next;
    next.alpha = 0;
    [self layOutType];
    if (!still) next.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(0, kPosterRise), kPosterScale, kPosterScale);
    [CATransaction commit];
    SGRAnimate(SGRMotionFade, ^{
        old.alpha = 0;
        next.alpha = 1;
        next.transform = CGAffineTransformIdentity;
    }, nil);
}

- (void)takeWord {
    [self paint];
}

// The words sung so far in the type color, the rest at the Words ahead opacity.
- (void)paint {
    if (!_attributes) return;
    NSInteger word = MIN(self.word, (NSInteger)_ranges.count - 1);
    NSUInteger sung = word >= 0 ? NSMaxRange(_ranges[(NSUInteger)word].rangeValue) : 0;
    NSMutableDictionary *ahead = [_attributes mutableCopy];
    ahead[NSForegroundColorAttributeName] = _ahead;
    NSMutableAttributedString *type = [[NSMutableAttributedString alloc] initWithString:_text attributes:ahead];
    [type addAttribute:NSForegroundColorAttributeName value:_ink range:NSMakeRange(0, sung)];
    _front.attributedText = type;
}

// The largest type the line fits at within the field's width and kPosterHeight of its height, each word on one
// line; the label in front sized to it, left-aligned with the field and centered on its centre line.
- (void)layOutType {
    if (!_text || !self.line) return;
    CGRect field = self.field;
    CGFloat width = field.size.width, tallest = field.size.height * kPosterHeight;
    if (width <= 0 || tallest <= 0) return;
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = NSTextAlignmentLeft;
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    NSDictionary *attributes;
    CGFloat height = 0;
    for (CGFloat size = kPosterLargest;; size = MAX(kPosterSmallest, floor(size * kPosterShrink))) {
        attributes = @{NSFontAttributeName: posterFont(size), NSParagraphStyleAttributeName: paragraph};
        height = ceil([_text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin
                                       attributes:attributes context:nil].size.height);
        BOOL wordsFit = YES;
        for (SGKaraokeWord *word in self.line.words) {
            if ([word.text ?: @"" sizeWithAttributes:attributes].width > width) { wordsFit = NO; break; }
        }
        if ((wordsFit && height <= tallest) || size <= kPosterSmallest) break;
    }
    _attributes = attributes;
    CGAffineTransform transform = _front.transform;
    _front.transform = CGAffineTransformIdentity;
    _front.bounds = CGRectMake(0, 0, width, MIN(height, tallest));
    _front.center = CGPointMake(CGRectGetMidX(field), self.centre);
    _front.transform = transform;
    [self paint];
}

@end

#pragma mark - Cut

// The word: heavy, as large as one line of the field's width allows, kCutLargest points at the most. The whole
// line: kCutLineSize points, its centre kCutLineAt of the field's height down. The blocks: kCutBlocks at
// kCutBlockOpacity, each kCutBlockWidth of the width plus up to as much again, kCutBlockHeight of the field's
// height plus up to kCutBlockGrow, scattered over kCutBlockSpread of its height around the word.
static const CGFloat kCutLargest = 132, kCutLineSize = 17, kCutLineAt = 0.66, kCutLineAlpha = 0.8;
enum { kCutBlocks = 3 };
static const CGFloat kCutBlockOpacity = 0.9, kCutBlockWidth = 0.3, kCutBlockHeight = 0.06, kCutBlockGrow = 0.18, kCutBlockSpread = 0.6;
// A cut's jump at Motion 1: kCutJumpScale larger and up to kCutJumpOffset points aside, settling over kCutSettle.
static const CGFloat kCutJumpScale = 0.06, kCutJumpOffset = 10;
static const CFTimeInterval kCutSettle = 0.28;
static NSString *const kCutJump = @"cut";

static UIFont *cutFont(CGFloat size) {
    return [UIFont systemFontOfSize:size weight:UIFontWeightHeavy];
}

// A well-mixed 32-bit hash, so neighboring words land far apart.
static uint32_t mixed(uint32_t x) {
    x ^= x >> 16;
    x *= 0x7feb352dU;
    x ^= x >> 15;
    x *= 0x846ca68bU;
    x ^= x >> 16;
    return x;
}

// A share from 0 to 1 for `seed`'s `salt`th draw.
static CGFloat share(uint32_t seed, uint32_t salt) {
    return (mixed(seed * 31U + salt) & 0xFFFF) / 65535.0;
}

@implementation SGRCutStage {
    CALayer *_coverLayer, *_shadeLayer;
    UIView *_cut;   // the blocks and the word, which jump together
    NSArray<CALayer *> *_blocks;
    UILabel *_wordLabel, *_lineLabel;
    NSString *_coverID;
    NSArray<UIColor *> *_colours;
    double _motion;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = UIColor.blackColor;
    _coverLayer = [CALayer layer];
    _coverLayer.contentsGravity = kCAGravityResizeAspectFill;
    _coverLayer.masksToBounds = YES;
    [self.layer addSublayer:_coverLayer];
    _shadeLayer = [CALayer layer];
    _shadeLayer.backgroundColor = UIColor.blackColor.CGColor;
    [self.layer addSublayer:_shadeLayer];
    _cut = [[UIView alloc] initWithFrame:CGRectZero];
    _cut.userInteractionEnabled = NO;
    [self addSubview:_cut];
    NSMutableArray *blocks = [NSMutableArray array];
    for (int i = 0; i < kCutBlocks; i++) {
        CALayer *block = [CALayer layer];
        block.opacity = kCutBlockOpacity;
        [_cut.layer addSublayer:block];
        [blocks addObject:block];
    }
    _blocks = blocks;
    _wordLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _wordLabel.textAlignment = NSTextAlignmentCenter;
    _wordLabel.numberOfLines = 1;
    [_cut addSubview:_wordLabel];
    _lineLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _lineLabel.font = [UIFont systemFontOfSize:kCutLineSize weight:UIFontWeightSemibold];
    _lineLabel.textAlignment = NSTextAlignmentCenter;
    _lineLabel.numberOfLines = 2;
    [self addSubview:_lineLabel];
    [self takeParams];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _coverLayer.frame = bounds;
    _shadeLayer.frame = bounds;
    [CATransaction commit];
    _cut.bounds = CGRectMake(0, 0, bounds.size.width, bounds.size.height);
    _cut.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
}

- (void)takeParams {
    UIColor *ink = SGColorRGB(lround(SGRVisualiserParam(SGRVisualiserCutID, SGRVisualiserInk)));
    _wordLabel.textColor = ink;
    _lineLabel.textColor = [ink colorWithAlphaComponent:kCutLineAlpha];
    _lineLabel.hidden = SGRVisualiserParam(SGRVisualiserCutID, SGRVisualiserSubtitle) == 0;
    _motion = SGRVisualiserParam(SGRVisualiserCutID, SGRVisualiserMotion);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _shadeLayer.opacity = (float)SGRVisualiserParam(SGRVisualiserCutID, SGRVisualiserShade);
    [CATransaction commit];
}

- (void)setCover:(UIImage *)cover identity:(NSString *)identity {
    if (identity == _coverID || [identity isEqualToString:_coverID]) return;
    _coverID = identity ? [identity copy] : nil;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _coverLayer.contents = identity ? (id)cover.CGImage : nil;
    [CATransaction commit];
}

- (void)setColours:(NSArray<UIColor *> *)colours {
    _colours = [colours copy];
    if (self.line) [self placeBlocks];
}

- (void)takeLine {
    _lineLabel.text = trimmed(SGKaraokeLineText(self.line));
    [self layOutLine];
    [self takeWord];
}

// The word whose start passed last, the line's first until one has: as large as fits, the blocks cut for it, and
// both jumping.
- (void)takeWord {
    [self layOutWord];
    [self placeBlocks];
    [self jump];
}

- (void)layOutType {
    if (!self.line) return;
    [self layOutLine];
    [self layOutWord];
    [self placeBlocks];
}

- (void)layOutLine {
    CGRect field = self.field;
    CGFloat height = ceil([_lineLabel sizeThatFits:CGSizeMake(field.size.width, CGFLOAT_MAX)].height);
    _lineLabel.bounds = CGRectMake(0, 0, field.size.width, height);
    _lineLabel.center = CGPointMake(CGRectGetMidX(field), CGRectGetMinY(field) + field.size.height * kCutLineAt);
}

- (void)layOutWord {
    NSArray<SGKaraokeWord *> *words = self.line.words;
    NSUInteger index = (NSUInteger)MAX(0, self.word);
    NSString *text = index < words.count ? trimmed(words[index].text ?: @"") : @"";
    CGRect field = self.field;
    CGFloat wide = [text sizeWithAttributes:@{NSFontAttributeName: cutFont(kCutLargest)}].width;
    CGFloat size = wide > field.size.width ? floor(kCutLargest * field.size.width / wide) : kCutLargest;
    _wordLabel.font = cutFont(size);
    _wordLabel.text = text;
    // In the container's coordinates, which are the stage's.
    CGFloat height = ceil(_wordLabel.font.lineHeight);
    _wordLabel.frame = CGRectMake(CGRectGetMinX(field), self.centre - height / 2, field.size.width, height);
}

// The seed the blocks and the jump are drawn from: the line's start and the word's index.
- (uint32_t)seed {
    return (uint32_t)self.line.start * 2654435761U ^ (uint32_t)MAX(0, self.word);
}

- (void)placeBlocks {
    CGFloat width = self.bounds.size.width, height = self.field.size.height;
    uint32_t seed = [self seed];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (NSUInteger i = 0; i < _blocks.count; i++) {
        uint32_t salt = (uint32_t)i * 5;
        CGFloat w = width * kCutBlockWidth * (1 + share(seed, salt));
        CGFloat h = height * (kCutBlockHeight + kCutBlockGrow * share(seed, salt + 1));
        CGFloat x = (width - w) * share(seed, salt + 2);
        CGFloat y = self.centre + height * kCutBlockSpread * (share(seed, salt + 3) - 0.5) - h / 2;
        _blocks[i].frame = CGRectMake(x, y, w, h);
        UIColor *colour = _colours.count ? _colours[mixed(seed + salt + 4) % _colours.count] : nil;
        _blocks[i].backgroundColor = colour.CGColor;
    }
    [CATransaction commit];
}

// A short jump in scale and offset that settles, by Motion; none with Reduce Motion or Motion at 0.
- (void)jump {
    [_cut.layer removeAnimationForKey:kCutJump];
    double motion = SGRReduceMotion() ? 0 : _motion;
    if (motion <= 0) return;
    uint32_t seed = [self seed];
    CGFloat dx = (2 * share(seed, 101) - 1) * kCutJumpOffset * motion, dy = (2 * share(seed, 102) - 1) * kCutJumpOffset * motion;
    CGFloat scale = 1 + kCutJumpScale * motion;
    CABasicAnimation *jump = [CABasicAnimation animationWithKeyPath:@"transform"];
    jump.fromValue = [NSValue valueWithCATransform3D:CATransform3DScale(CATransform3DMakeTranslation(dx, dy, 0), scale, scale, 1)];
    jump.toValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
    jump.duration = kCutSettle;
    jump.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [_cut.layer addAnimation:jump forKey:kCutJump];
}

@end
