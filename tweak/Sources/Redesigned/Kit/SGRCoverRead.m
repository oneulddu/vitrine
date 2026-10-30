#import <Vision/Vision.h>
#import "Core/SGCore.h"
#import "SGRCoverRead.h"
#import "SGRTokens.h"

// The picture as read: aspect-filled into the bitmap, averaged in blocks into the sample.
enum {
    kBitmapSide = 256,
    kSampleSide = 64,
    kBlock = kBitmapSide / kSampleSide,
    kSampleCount = kSampleSide * kSampleSide,
    kClusterCount = 6,
};
static const CGFloat kOpaqueAlpha = 0.5;          // a sample pixel under this is left out
static const CGFloat kMinOpaqueShare = 0.25;      // and a picture with less of it than this is not read
static const CGFloat kMinWidthPoints = 80;
static const size_t kBorderRows = 3, kFootRows = 9;
static const size_t kClusterIterations = 12;
static const NSUInteger kCacheCount = 64;
// Solid: the border's share near its median, and the whole picture's.
static const CGFloat kBorderNear = 0.05, kBorderNearShare = 0.85, kAllNear = 0.06, kAllNearShare = 0.55;
static const CGFloat kSolidDarkL = 0.35, kSolidLightL = 0.85, kSolidLightChroma = 0.04;
// A row of a solid picture with this many pixels farther than kAllNear from the border's colour holds content.
static const size_t kContentPixels = 2;
// Dark with an accent.
static const CGFloat kDarkMeanL = 0.33, kDarkPixelL = 0.25, kDarkShare = 0.60;
static const CGFloat kAccentChroma = 0.08, kAccentCoverage = 0.15, kAccentMinL = 0.15, kAccentMaxL = 0.9;
// A portrait: faces covering this share of the picture, the lowest edge at or below this fraction of its height.
static const CGFloat kPortraitFaceArea = 0.05, kPortraitFaceBottom = 0.5;
static const CGFloat kColourfulChroma = 0.06;
static const CGFloat kSalientConfidence = 0.5;
// The page colour.
static const CGFloat kPageMaxL = 0.44, kPageMaxLContrast = 0.40, kChromaLift = 1.15, kLiftFromChroma = 0.03;
// The sharp end: a solid picture's content and this much more, at most kSolidSharpMax; any other held between these.
static const CGFloat kSolidSharpMargin = 0.05, kSolidSharpMax = 0.86, kSharpMin = 0.60, kSharpMax = 0.90;
static const CGFloat kSolidBlurPoints = 24, kBlurPoints = 64, kSolidDarkMixPoints = 120;
// A solid dark picture's border and its page colour this close are the same colour.
static const CGFloat kSameColour = 0.02;
static const NSUInteger kLoggedReadings = 8;
// The artist's photo: its foot, and the foot's chroma held to this once lifted.
static const size_t kPhotoFootRows = 12;
static const CGFloat kPhotoMaxChroma = 0.15;
// The foot's colour takes the page from the current one with this much more chroma, at least kPhotoMinChroma, and its
// hue outside the skin and yellow band, in degrees.
static const CGFloat kPhotoChromaGain = 0.04, kPhotoMinChroma = 0.06, kSkinHueFromDegrees = 70, kSkinHueToDegrees = 115;
// A very dark photo, and how much lighter than its foot its page colour may be.
static const CGFloat kPhotoDarkL = 0.24, kPhotoDarkMargin = 0.02;

BOOL SGRCoverKindIsSolid(SGRCoverKind kind) {
    return kind == SGRCoverKindSolidDark || kind == SGRCoverKindSolidLight || kind == SGRCoverKindSolidColour;
}

#pragma mark - OKLab

static CGFloat decode(CGFloat c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

static CGFloat encode(CGFloat c) {
    return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055;
}

static SGRLab labFromLinear(CGFloat r, CGFloat g, CGFloat b) {
    CGFloat l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    CGFloat m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    CGFloat s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    return (SGRLab){0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s};
}

static void linearFromLab(SGRLab lab, CGFloat linear[3]) {
    CGFloat l = lab.L + 0.3963377774 * lab.a + 0.2158037573 * lab.b;
    CGFloat m = lab.L - 0.1055613458 * lab.a - 0.0638541728 * lab.b;
    CGFloat s = lab.L - 0.0894841775 * lab.a - 1.2914855480 * lab.b;
    l = l * l * l;
    m = m * m * m;
    s = s * s * s;
    linear[0] = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
    linear[1] = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
    linear[2] = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;
}

SGRLab SGRLabFromRGB(CGFloat red, CGFloat green, CGFloat blue) {
    return labFromLinear(decode(red), decode(green), decode(blue));
}

void SGRLabToRGB(SGRLab lab, CGFloat *red, CGFloat *green, CGFloat *blue) {
    CGFloat linear[3];
    linearFromLab(lab, linear);
    *red = encode(MIN(MAX(linear[0], 0), 1));
    *green = encode(MIN(MAX(linear[1], 0), 1));
    *blue = encode(MIN(MAX(linear[2], 0), 1));
}

// sRGB levels to linear, and linear in kEncodeSteps steps back to levels.
enum { kEncodeSteps = 4096 };
static const float *decodeTable(void) {
    static float table[256];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (size_t i = 0; i < 256; i++) table[i] = (float)decode(i / 255.0);
    });
    return table;
}

static const uint8_t *encodeTable(void) {
    static uint8_t table[kEncodeSteps + 1];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (size_t i = 0; i <= kEncodeSteps; i++) table[i] = (uint8_t)lround(encode((CGFloat)i / kEncodeSteps) * 255);
    });
    return table;
}

SGRLab SGRLabFromRGB8(const uint8_t rgb[3]) {
    const float *table = decodeTable();
    return labFromLinear(table[rgb[0]], table[rgb[1]], table[rgb[2]]);
}

void SGRLabToRGB8(SGRLab lab, uint8_t rgb[3]) {
    const uint8_t *table = encodeTable();
    CGFloat linear[3];
    linearFromLab(lab, linear);
    for (int i = 0; i < 3; i++) rgb[i] = table[(size_t)lround(MIN(MAX(linear[i], 0), 1) * kEncodeSteps)];
}

CGFloat SGRLabDistance(SGRLab one, SGRLab other) {
    CGFloat dL = one.L - other.L, da = one.a - other.a, db = one.b - other.b;
    return sqrt(dL * dL + da * da + db * db);
}

static CGFloat chromaOf(SGRLab lab) {
    return hypot(lab.a, lab.b);
}

static BOOL inGamut(SGRLab lab) {
    static const CGFloat slack = 1e-7;
    CGFloat linear[3];
    linearFromLab(lab, linear);
    for (int i = 0; i < 3; i++) {
        if (linear[i] < -slack || linear[i] > 1 + slack) return NO;
    }
    return YES;
}

static CGFloat pageMaxL(BOOL contrast) {
    return contrast ? kPageMaxLContrast : kPageMaxL;
}

// A page colour at lightness L (already held), `chroma` and `hue` (radians), brought into sRGB by its chroma alone.
static SGRLab pageAt(CGFloat L, CGFloat chroma, CGFloat hue) {
    SGRLab page = {L, chroma * cos(hue), chroma * sin(hue)};
    if (inGamut(page)) return page;
    // Out of sRGB: the most chroma at this lightness and hue that is in it. Gray at L <= 0.44 always is.
    CGFloat inside = 0, outside = chroma;
    for (int i = 0; i < 24; i++) {
        CGFloat mid = (inside + outside) / 2;
        if (inGamut((SGRLab){L, mid * cos(hue), mid * sin(hue)})) inside = mid;
        else outside = mid;
    }
    return (SGRLab){L, inside * cos(hue), inside * sin(hue)};
}

SGRLab SGRCoverPageLab(SGRLab colour, BOOL contrast) {
    CGFloat chroma = chromaOf(colour), hue = atan2(colour.b, colour.a);
    if (chroma >= kLiftFromChroma) chroma *= kChromaLift;
    return pageAt(MIN(colour.L, pageMaxL(contrast)), chroma, hue);
}

#pragma mark - the reading

@implementation SGRCoverReading

- (instancetype)initWithKind:(SGRCoverKind)kind colour:(SGRLab)colour contentBottom:(CGFloat)contentBottom
               subjectBottom:(CGFloat)subjectBottom identity:(uint64_t)identity final:(BOOL)final {
    if (!(self = [super init])) return nil;
    _kind = kind;
    _colour = colour;
    _contentBottom = contentBottom;
    _subjectBottom = subjectBottom;
    _identity = identity;
    _final = final;
    return self;
}

- (UIColor *)pageColor {
    CGFloat r, g, b;
    SGRLabToRGB(SGRCoverPageLab(_colour, SGRIncreaseContrast()), &r, &g, &b);
    return [UIColor colorWithRed:r green:g blue:b alpha:1];
}

@end

SGRCoverSharpness SGRCoverSharpnessFor(SGRCoverReading *reading, CGFloat fallback) {
    if (SGRCoverKindIsSolid(reading.kind)) {
        SGRCoverSharpness sharpness = {MIN(reading.contentBottom + kSolidSharpMargin, kSolidSharpMax), kSolidBlurPoints, 0};
        SGRLab page = SGRCoverPageLab(reading.colour, SGRIncreaseContrast());
        if (reading.kind == SGRCoverKindSolidDark && SGRLabDistance(page, reading.colour) < kSameColour) {
            sharpness.blurRadius = 0;
            sharpness.mixLength = kSolidDarkMixPoints;
        }
        return sharpness;
    }
    return (SGRCoverSharpness){MIN(MAX(MAX(fallback, reading.subjectBottom), kSharpMin), kSharpMax), kBlurPoints, 0};
}

#pragma mark - the photo's reading

@implementation SGRPhotoReading

- (instancetype)initWithFoot:(SGRLab)foot meanL:(CGFloat)meanL largestFace:(CGFloat)largestFace faceCount:(NSUInteger)faceCount
                    identity:(uint64_t)identity {
    if (!(self = [super init])) return nil;
    _foot = foot;
    _meanL = meanL;
    _largestFace = largestFace;
    _faceCount = faceCount;
    _identity = identity;
    return self;
}

@end

static CGFloat hueDegrees(SGRLab lab) {
    CGFloat hue = atan2(lab.b, lab.a) * 180 / M_PI;
    return hue < 0 ? hue + 360 : hue;
}

SGRLab SGRPhotoPageLab(SGRPhotoReading *reading, SGRLab current, BOOL contrast) {
    SGRLab foot = reading.foot, chosen = current;
    CGFloat footChroma = chromaOf(foot), hue = hueDegrees(foot);
    BOOL skin = hue >= kSkinHueFromDegrees && hue <= kSkinHueToDegrees;
    if (footChroma >= chromaOf(current) + kPhotoChromaGain && footChroma >= kPhotoMinChroma && !skin) chosen = foot;
    if (reading.meanL < kPhotoDarkL && chosen.L > foot.L + kPhotoDarkMargin) chosen.L = foot.L;
    return pageAt(MIN(chosen.L, pageMaxL(contrast)), chromaOf(chosen), atan2(chosen.b, chosen.a));
}

UIColor *SGRPhotoPageColor(SGRPhotoReading *reading, UIColor *current) {
    CGFloat r, g, b, a;
    [current getRed:&r green:&g blue:&b alpha:&a];
    SGRLabToRGB(SGRPhotoPageLab(reading, SGRLabFromRGB(r, g, b), SGRIncreaseContrast()), &r, &g, &b);
    return [UIColor colorWithRed:r green:g blue:b alpha:1];
}

#pragma mark - measuring

typedef struct {
    SGRLab lab[kSampleCount];
    bool opaque[kSampleCount];
    size_t opaqueCount;
    uint64_t identity;
} Sample;

typedef struct {
    SGRLab centre;
    CGFloat coverage, chroma;
} Cluster;

typedef struct {
    SGRLab border;
    CGFloat borderNear, allNear, contentBottom;
    CGFloat meanL, meanChroma, darkShare;
    Cluster clusters[kClusterCount];
} Measures;

static CGColorSpaceRef sRGB(void) {
    static CGColorSpaceRef space;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB); });
    return space;
}

// The picture aspect-filled into the bitmap, and the sample averaged from it; nil when too little of it is opaque.
static CGImageRef newBitmap(UIImage *image, Sample *sample) {
    CGContextRef context = CGBitmapContextCreate(NULL, kBitmapSide, kBitmapSide, 8, kBitmapSide * 4, sRGB(),
                                                 (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    if (!context) return NULL;
    CGContextTranslateCTM(context, 0, kBitmapSide);
    CGContextScaleCTM(context, 1, -1);
    CGSize size = image.size;
    CGFloat scale = MAX(kBitmapSide / size.width, kBitmapSide / size.height);
    CGSize drawn = CGSizeMake(size.width * scale, size.height * scale);
    UIGraphicsPushContext(context);
    [image drawInRect:CGRectMake((kBitmapSide - drawn.width) / 2, (kBitmapSide - drawn.height) / 2, drawn.width, drawn.height)];
    UIGraphicsPopContext();

    const uint8_t *pixels = CGBitmapContextGetData(context);
    size_t rowBytes = CGBitmapContextGetBytesPerRow(context);
    uint64_t hash = 0xcbf29ce484222325ULL;
    sample->opaqueCount = 0;
    for (size_t y = 0; y < kSampleSide; y++) {
        for (size_t x = 0; x < kSampleSide; x++) {
            NSUInteger sums[4] = {0, 0, 0, 0};
            for (size_t dy = 0; dy < kBlock; dy++) {
                const uint8_t *row = pixels + (y * kBlock + dy) * rowBytes + x * kBlock * 4;
                for (size_t dx = 0; dx < kBlock * 4; dx++) sums[dx % 4] += row[dx];
            }
            size_t i = y * kSampleSide + x;
            CGFloat alpha = sums[3] / (255.0 * kBlock * kBlock);
            sample->opaque[i] = alpha >= kOpaqueAlpha;
            uint8_t levels[4] = {0, 0, 0, (uint8_t)lround(alpha * 255)};
            if (sums[3] > 0) {
                // Premultiplied: the colour is the sum over the alpha's.
                for (int c = 0; c < 3; c++) levels[c] = (uint8_t)MIN(255, lround(255.0 * sums[c] / sums[3]));
            }
            sample->lab[i] = SGRLabFromRGB(levels[0] / 255.0, levels[1] / 255.0, levels[2] / 255.0);
            if (sample->opaque[i]) sample->opaqueCount++;
            for (int c = 0; c < 4; c++) hash = (hash ^ levels[c]) * 0x100000001b3ULL;
        }
    }
    sample->identity = hash;
    CGImageRef bitmap = sample->opaqueCount >= kSampleCount * kMinOpaqueShare ? CGBitmapContextCreateImage(context) : NULL;
    CGContextRelease(context);
    return bitmap;
}

static int compareFloats(const void *one, const void *other) {
    CGFloat a = *(const CGFloat *)one, b = *(const CGFloat *)other;
    return a < b ? -1 : a > b;
}

static CGFloat median(CGFloat *values, size_t count) {
    qsort(values, count, sizeof(CGFloat), compareFloats);
    return count % 2 ? values[count / 2] : (values[count / 2 - 1] + values[count / 2]) / 2;
}

// The per-component median of the opaque samples `include` says yes to; NO when there is none.
static BOOL medianOf(const Sample *sample, BOOL (^include)(size_t x, size_t y), SGRLab *result) {
    CGFloat *L = malloc(sizeof(CGFloat) * kSampleCount), *a = malloc(sizeof(CGFloat) * kSampleCount),
            *b = malloc(sizeof(CGFloat) * kSampleCount);
    size_t count = 0;
    for (size_t y = 0; y < kSampleSide; y++) {
        for (size_t x = 0; x < kSampleSide; x++) {
            size_t i = y * kSampleSide + x;
            if (!sample->opaque[i] || !include(x, y)) continue;
            L[count] = sample->lab[i].L;
            a[count] = sample->lab[i].a;
            b[count] = sample->lab[i].b;
            count++;
        }
    }
    if (count) *result = (SGRLab){median(L, count), median(a, count), median(b, count)};
    free(L);
    free(a);
    free(b);
    return count > 0;
}

static BOOL inBorderRows(size_t y) {
    return y < kBorderRows || y >= kSampleSide - kBorderRows;
}

static BOOL inBorderColumns(size_t x) {
    return x < kBorderRows || x >= kSampleSide - kBorderRows;
}

typedef struct {
    CGFloat L;
    size_t index;
} Ranked;

static int compareRanked(const void *one, const void *other) {
    CGFloat a = ((const Ranked *)one)->L, b = ((const Ranked *)other)->L;
    return a < b ? -1 : a > b;
}

// k-means from the samples at the six quantiles of lightness, so the same picture always clusters the same.
static void cluster(const Sample *sample, Cluster clusters[kClusterCount]) {
    size_t count = sample->opaqueCount;
    Ranked *ranked = malloc(sizeof(Ranked) * count);
    size_t n = 0;
    for (size_t i = 0; i < kSampleCount; i++) {
        if (sample->opaque[i]) ranked[n++] = (Ranked){sample->lab[i].L, i};
    }
    qsort(ranked, count, sizeof(Ranked), compareRanked);
    SGRLab centres[kClusterCount];
    for (size_t k = 0; k < kClusterCount; k++) centres[k] = sample->lab[ranked[(size_t)((k + 0.5) * count / kClusterCount)].index];
    free(ranked);

    size_t members[kClusterCount];
    for (size_t pass = 0; pass <= kClusterIterations; pass++) {
        SGRLab sums[kClusterCount] = {{0}};
        memset(members, 0, sizeof(members));
        for (size_t i = 0; i < kSampleCount; i++) {
            if (!sample->opaque[i]) continue;
            size_t nearest = 0;
            CGFloat best = CGFLOAT_MAX;
            for (size_t k = 0; k < kClusterCount; k++) {
                CGFloat distance = SGRLabDistance(sample->lab[i], centres[k]);
                if (distance < best) {
                    best = distance;
                    nearest = k;
                }
            }
            members[nearest]++;
            sums[nearest].L += sample->lab[i].L;
            sums[nearest].a += sample->lab[i].a;
            sums[nearest].b += sample->lab[i].b;
        }
        // The last pass only counts the members of the centres the iterations settled on.
        if (pass == kClusterIterations) break;
        for (size_t k = 0; k < kClusterCount; k++) {
            if (members[k]) centres[k] = (SGRLab){sums[k].L / members[k], sums[k].a / members[k], sums[k].b / members[k]};
        }
    }
    for (size_t k = 0; k < kClusterCount; k++) {
        clusters[k] = (Cluster){centres[k], (CGFloat)members[k] / count, chromaOf(centres[k])};
    }
}

static Measures measure(const Sample *sample) {
    Measures m = {{0}};
    // The border's median, the corners counted in both their row and their column.
    CGFloat *L = malloc(sizeof(CGFloat) * kSampleCount * 2), *a = malloc(sizeof(CGFloat) * kSampleCount * 2),
            *b = malloc(sizeof(CGFloat) * kSampleCount * 2);
    SGRLab *border = malloc(sizeof(SGRLab) * kSampleCount * 2);
    size_t borderCount = 0;
    for (size_t y = 0; y < kSampleSide; y++) {
        for (size_t x = 0; x < kSampleSide; x++) {
            size_t i = y * kSampleSide + x;
            if (!sample->opaque[i]) continue;
            int times = inBorderRows(y) + inBorderColumns(x);
            for (int t = 0; t < times; t++) {
                border[borderCount] = sample->lab[i];
                L[borderCount] = sample->lab[i].L;
                a[borderCount] = sample->lab[i].a;
                b[borderCount] = sample->lab[i].b;
                borderCount++;
            }
        }
    }
    if (borderCount) {
        m.border = (SGRLab){median(L, borderCount), median(a, borderCount), median(b, borderCount)};
        size_t near = 0;
        for (size_t i = 0; i < borderCount; i++) near += SGRLabDistance(border[i], m.border) <= kBorderNear;
        m.borderNear = (CGFloat)near / borderCount;
    }
    free(L);
    free(a);
    free(b);
    free(border);

    size_t near = 0, dark = 0, lowest = 0;
    CGFloat sumL = 0, sumChroma = 0;
    for (size_t y = 0; y < kSampleSide; y++) {
        size_t content = 0;
        for (size_t x = 0; x < kSampleSide; x++) {
            size_t i = y * kSampleSide + x;
            if (!sample->opaque[i]) continue;
            SGRLab lab = sample->lab[i];
            BOOL close = borderCount && SGRLabDistance(lab, m.border) <= kAllNear;
            near += close;
            content += !close;
            dark += lab.L < kDarkPixelL;
            sumL += lab.L;
            sumChroma += chromaOf(lab);
        }
        if (content >= kContentPixels) lowest = y + 1;
    }
    size_t count = sample->opaqueCount;
    m.allNear = (CGFloat)near / count;
    m.contentBottom = (CGFloat)lowest / kSampleSide;
    m.meanL = sumL / count;
    m.meanChroma = sumChroma / count;
    m.darkShare = (CGFloat)dark / count;
    cluster(sample, m.clusters);
    return m;
}

static BOOL isSolid(const Measures *m) {
    return m->borderNear >= kBorderNearShare && m->allNear >= kAllNearShare;
}

static BOOL inAny(NSArray<NSValue *> *rects, size_t x, size_t y) {
    CGPoint centre = CGPointMake((x + 0.5) / kSampleSide, (y + 0.5) / kSampleSide);
    for (NSValue *rect in rects) {
        if (CGRectContainsPoint(rect.CGRectValue, centre)) return YES;
    }
    return NO;
}

// The foot's colour, without the faces' pixels while any of the foot is outside them.
static SGRLab footColour(const Sample *sample, NSArray<NSValue *> *faces) {
    SGRLab colour = {0};
    BOOL (^foot)(size_t, size_t) = ^BOOL(size_t x, size_t y) { return y >= kSampleSide - kFootRows; };
    if (faces.count && medianOf(sample, ^BOOL(size_t x, size_t y) { return foot(x, y) && !inAny(faces, x, y); }, &colour)) return colour;
    if (medianOf(sample, foot, &colour)) return colour;
    // A picture whose foot is all transparent: its border's, which every read picture has.
    medianOf(sample, ^BOOL(size_t x, size_t y) { return inBorderRows(y) || inBorderColumns(x); }, &colour);
    return colour;
}

// `faces` and `objects` nil for the pixel-only reading.
static SGRCoverReading *classify(const Sample *sample, const Measures *m, NSArray<NSValue *> *faces, NSArray<NSValue *> *objects, BOOL final) {
    if (isSolid(m)) {
        SGRLab border = m->border;
        CGFloat chroma = chromaOf(border);
        SGRCoverKind kind = border.L < kSolidDarkL ? SGRCoverKindSolidDark
                          : border.L > kSolidLightL && chroma < kSolidLightChroma ? SGRCoverKindSolidLight : SGRCoverKindSolidColour;
        return [[SGRCoverReading alloc] initWithKind:kind colour:border contentBottom:m->contentBottom subjectBottom:0
                                            identity:sample->identity final:final];
    }
    CGFloat subjectBottom = 0, faceArea = 0, faceBottom = 0;
    for (NSValue *face in faces) {
        CGRect rect = face.CGRectValue;
        faceArea += rect.size.width * rect.size.height;
        faceBottom = MAX(faceBottom, CGRectGetMaxY(rect));
    }
    subjectBottom = faceBottom;
    for (NSValue *object in objects) subjectBottom = MAX(subjectBottom, CGRectGetMaxY(object.CGRectValue));
    SGRCoverReading *(^reading)(SGRCoverKind, SGRLab) = ^SGRCoverReading *(SGRCoverKind kind, SGRLab colour) {
        return [[SGRCoverReading alloc] initWithKind:kind colour:colour contentBottom:1 subjectBottom:subjectBottom
                                            identity:sample->identity final:final];
    };

    if (m->meanL < kDarkMeanL || m->darkShare >= kDarkShare) {
        const Cluster *accent = NULL;
        for (size_t k = 0; k < kClusterCount; k++) {
            const Cluster *c = &m->clusters[k];
            if (c->chroma < kAccentChroma || c->coverage < kAccentCoverage || c->centre.L <= kAccentMinL || c->centre.L >= kAccentMaxL) continue;
            if (!accent || c->coverage > accent->coverage || (c->coverage == accent->coverage && c->chroma > accent->chroma)) accent = c;
        }
        if (accent) return reading(SGRCoverKindDarkAccent, accent->centre);
    }
    if (faceArea >= kPortraitFaceArea && faceBottom >= kPortraitFaceBottom) return reading(SGRCoverKindPortrait, footColour(sample, faces));
    if (m->meanChroma >= kColourfulChroma) {
        const Cluster *best = &m->clusters[0];
        for (size_t k = 1; k < kClusterCount; k++) {
            if (m->clusters[k].coverage * m->clusters[k].chroma > best->coverage * best->chroma) best = &m->clusters[k];
        }
        return reading(SGRCoverKindColourful, best->centre);
    }
    return reading(SGRCoverKindFoot, footColour(sample, nil));
}

static SGRLab meanOf(SGRLab sum, size_t count) {
    return (SGRLab){sum.L / count, sum.a / count, sum.b / count};
}

// The photo's reading from its sample and the faces Vision found in it (none when it failed).
static SGRPhotoReading *readPhoto(const Sample *sample, NSArray<NSValue *> *faces) {
    static const CGRect whole = {{0, 0}, {1, 1}};
    CGFloat largest = 0;
    for (NSValue *face in faces) {
        CGRect shown = CGRectIntersection(face.CGRectValue, whole);
        if (!CGRectIsNull(shown)) largest = MAX(largest, shown.size.width * shown.size.height);
    }
    SGRLab all = {0}, foot = {0}, outside = {0};
    size_t footCount = 0, outsideCount = 0;
    for (size_t y = 0; y < kSampleSide; y++) {
        for (size_t x = 0; x < kSampleSide; x++) {
            size_t i = y * kSampleSide + x;
            if (!sample->opaque[i]) continue;
            SGRLab lab = sample->lab[i];
            all = (SGRLab){all.L + lab.L, all.a + lab.a, all.b + lab.b};
            if (y < kSampleSide - kPhotoFootRows) continue;
            foot = (SGRLab){foot.L + lab.L, foot.a + lab.a, foot.b + lab.b};
            footCount++;
            if (inAny(faces, x, y)) continue;
            outside = (SGRLab){outside.L + lab.L, outside.a + lab.a, outside.b + lab.b};
            outsideCount++;
        }
    }
    // The foot outside the faces, else all of it; a photo whose foot is all transparent, the whole photo's.
    SGRLab colour = outsideCount ? meanOf(outside, outsideCount) : footCount ? meanOf(foot, footCount) : meanOf(all, sample->opaqueCount);
    CGFloat chroma = chromaOf(colour), hue = atan2(colour.b, colour.a);
    if (chroma >= kLiftFromChroma) chroma = MIN(chroma * kChromaLift, kPhotoMaxChroma);
    colour = (SGRLab){colour.L, chroma * cos(hue), chroma * sin(hue)};
    return [[SGRPhotoReading alloc] initWithFoot:colour meanL:all.L / sample->opaqueCount largestFace:largest faceCount:faces.count
                                        identity:sample->identity];
}

#pragma mark - Vision

static CGRect fromVision(CGRect box) {
    return CGRectMake(box.origin.x, 1 - CGRectGetMaxY(box), box.size.width, box.size.height);
}

// Faces, and with `salient` salient objects, in one handler; NO on an error.
static BOOL detect(CGImageRef bitmap, BOOL salient, NSArray<NSValue *> **faces, NSArray<NSValue *> **objects) {
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:bitmap options:@{}];
    VNDetectFaceRectanglesRequest *faceRequest = [VNDetectFaceRectanglesRequest new];
    VNGenerateObjectnessBasedSaliencyImageRequest *saliency = salient ? [VNGenerateObjectnessBasedSaliencyImageRequest new] : nil;
    NSError *error = nil;
    if (![handler performRequests:saliency ? @[faceRequest, saliency] : @[faceRequest] error:&error]) {
        static BOOL logged;
        if (!logged) {
            logged = YES;
            SGLog(@"redesign kit: cover read without Vision, %@", error.localizedDescription);
        }
        return NO;
    }
    NSMutableArray<NSValue *> *foundFaces = [NSMutableArray array], *foundObjects = [NSMutableArray array];
    for (VNFaceObservation *face in faceRequest.results) [foundFaces addObject:[NSValue valueWithCGRect:fromVision(face.boundingBox)]];
    for (VNSaliencyImageObservation *map in saliency.results) {
        for (VNRectangleObservation *object in map.salientObjects) {
            if (object.confidence > kSalientConfidence) [foundObjects addObject:[NSValue valueWithCGRect:fromVision(object.boundingBox)]];
        }
    }
    *faces = foundFaces;
    *objects = foundObjects;
    return YES;
}

static BOOL visionSubjects(CGImageRef bitmap, NSArray<NSValue *> **faces, NSArray<NSValue *> **objects) {
    return detect(bitmap, YES, faces, objects);
}

static BOOL visionFaces(CGImageRef bitmap, NSArray<NSValue *> **faces, NSArray<NSValue *> **objects) {
    return detect(bitmap, NO, faces, objects);
}

// `vision` on the bitmap, or the harness's answer for it.
static BOOL look(CGImageRef bitmap, BOOL (*vision)(CGImageRef, NSArray<NSValue *> **, NSArray<NSValue *> **),
                 NSArray<NSValue *> **faces, NSArray<NSValue *> **objects) {
#ifdef SGR_COVER_READ_TEST
    return SGRCoverReadTestSubjects(bitmap, vision, faces, objects);
#else
    return vision(bitmap, faces, objects);
#endif
}

#pragma mark - reading

static dispatch_queue_t readQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("spotifyglass.redesign.coverRead", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    });
    return queue;
}

// Readings by the sample's content, kCacheCount of them: one for covers, one for photos.
static NSCache *newReadingCache(void) {
    NSCache *cache = [NSCache new];
    cache.countLimit = kCacheCount;
    return cache;
}

// Readings by the UIImage, held weakly.
static NSMapTable *newImageTable(void) {
    return [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality
                                     valueOptions:NSPointerFunctionsStrongMemory capacity:0];
}

static NSCache<NSNumber *, SGRCoverReading *> *readings(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = newReadingCache(); });
    return cache;
}

// Main thread only.
static NSMapTable<UIImage *, SGRCoverReading *> *readImages(void) {
    static NSMapTable *table;
    if (!table) table = newImageTable();
    return table;
}

static NSCache<NSNumber *, SGRPhotoReading *> *photoReadings(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = newReadingCache(); });
    return cache;
}

// Main thread only.
static NSMapTable<UIImage *, SGRPhotoReading *> *readPhotos(void) {
    static NSMapTable *table;
    if (!table) table = newImageTable();
    return table;
}

static NSString *kindName(SGRCoverKind kind) {
    return @[@"foot", @"solid dark", @"solid light", @"solid colour", @"dark accent", @"portrait", @"colourful"][kind];
}

static void deliver(UIImage *image, SGRCoverReading *reading, CFTimeInterval started, void (^done)(SGRCoverReading *)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (reading.final) {
            [readImages() setObject:reading forKey:image];
            static NSUInteger logged;
            if (logged++ < kLoggedReadings)
                SGLog(@"redesign kit: cover read as %@, L %.2f C %.3f, in %.0f ms", kindName(reading.kind), reading.colour.L,
                      chromaOf(reading.colour), (CACurrentMediaTime() - started) * 1000);
        }
        done(reading);
    });
}

BOOL SGRCoverRead(UIImage *image, void (^done)(SGRCoverReading *reading)) {
    if (!image || image.size.width < kMinWidthPoints) return NO;
    SGRCoverReading *known = [readImages() objectForKey:image];
    if (known) {
        dispatch_async(dispatch_get_main_queue(), ^{ done(known); });
        return YES;
    }
    CFTimeInterval started = CACurrentMediaTime();
    dispatch_async(readQueue(), ^{
        @autoreleasepool {
            Sample *sample = malloc(sizeof(Sample));
            CGImageRef bitmap = newBitmap(image, sample);
            if (!bitmap) {
                free(sample);
                dispatch_async(dispatch_get_main_queue(), ^{ done(nil); });
                return;
            }
            SGRCoverReading *cached = [readings() objectForKey:@(sample->identity)];
            if (cached) {
                deliver(image, cached, started, done);
            } else {
                Measures m = measure(sample);
                BOOL solid = isSolid(&m);
                SGRCoverReading *pixels = classify(sample, &m, nil, nil, solid);
                SGRCoverReading *final = pixels;
                if (!solid) {
                    deliver(image, pixels, started, done);
                    NSArray<NSValue *> *faces = nil, *objects = nil;
                    BOOL seen = look(bitmap, visionSubjects, &faces, &objects);
                    final = classify(sample, &m, seen ? faces : @[], seen ? objects : @[], YES);
                }
                [readings() setObject:final forKey:@(sample->identity)];
                deliver(image, final, started, done);
            }
            CGImageRelease(bitmap);
            free(sample);
        }
    });
    return YES;
}

static void deliverPhoto(UIImage *image, SGRPhotoReading *reading, CFTimeInterval started, void (^done)(SGRPhotoReading *)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (reading) [readPhotos() setObject:reading forKey:image];
        static NSUInteger logged;
        if (reading && logged++ < kLoggedReadings)
            SGLog(@"redesign kit: photo read, %lu faces, the largest %.3f of it, mean L %.2f, foot L %.2f C %.3f h %.0f, in %.0f ms",
                  (unsigned long)reading.faceCount, reading.largestFace, reading.meanL, reading.foot.L, chromaOf(reading.foot),
                  hueDegrees(reading.foot), (CACurrentMediaTime() - started) * 1000);
        done(reading);
    });
}

BOOL SGRPhotoRead(UIImage *image, void (^done)(SGRPhotoReading *reading)) {
    if (!image || image.size.width < kMinWidthPoints) return NO;
    SGRPhotoReading *known = [readPhotos() objectForKey:image];
    if (known) {
        dispatch_async(dispatch_get_main_queue(), ^{ done(known); });
        return YES;
    }
    CFTimeInterval started = CACurrentMediaTime();
    dispatch_async(readQueue(), ^{
        @autoreleasepool {
            Sample *sample = malloc(sizeof(Sample));
            CGImageRef bitmap = newBitmap(image, sample);
            SGRPhotoReading *reading = nil;
            if (bitmap) {
                reading = [photoReadings() objectForKey:@(sample->identity)];
                if (!reading) {
                    NSArray<NSValue *> *faces = nil, *objects = nil;
                    BOOL seen = look(bitmap, visionFaces, &faces, &objects);
                    reading = readPhoto(sample, seen ? faces : @[]);
                    [photoReadings() setObject:reading forKey:@(sample->identity)];
                }
            }
            CGImageRelease(bitmap);
            free(sample);
            deliverPhoto(image, reading, started, done);
        }
    });
    return YES;
}
