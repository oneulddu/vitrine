// The artist photos the picture-aware photo is checked on (photo-read-check.m, photo-hero-check.m), drawn in code at
// 600 x 600: nothing is read from disk. The four drawn people are softened so that Vision itself finds their faces.
#import <CoreImage/CoreImage.h>
#import <UIKit/UIKit.h>

static const CGFloat kPhotoSide = 600;
static const CGGradientDrawingOptions kPhotoGradientCovers = kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation;

static UIImage *photo(void (^draw)(CGContextRef c, CGFloat side)) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(kPhotoSide, kPhotoSide) format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) { draw(context.CGContext, kPhotoSide); }];
}

static void paint(CGContextRef c, CGRect rect, CGFloat r, CGFloat g, CGFloat b) {
    CGContextSetRGBFillColor(c, r, g, b, 1);
    CGContextFillRect(c, rect);
}

static void oval(CGContextRef c, CGRect rect, CGFloat r, CGFloat g, CGFloat b) {
    CGContextSetRGBFillColor(c, r, g, b, 1);
    CGContextFillEllipseInRect(c, rect);
}

static void verticalGradient(CGContextRef c, CGFloat side, const CGFloat top[3], const CGFloat bottom[3]) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat stops[] = {top[0], top[1], top[2], 1, bottom[0], bottom[1], bottom[2], 1};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, stops, NULL, 2);
    CGContextDrawLinearGradient(c, gradient, CGPointZero, CGPointMake(0, side), kPhotoGradientCovers);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
}

// A head `w` wide (the face's own width) centred on (x, y), with hair, neck and shoulders in `shirt`.
static void person(CGContextRef c, CGFloat x, CGFloat y, CGFloat w, const CGFloat shirt[3]) {
    CGRect (^at)(CGFloat, CGFloat, CGFloat, CGFloat) = ^CGRect(CGFloat dx, CGFloat dy, CGFloat width, CGFloat height) {
        return CGRectMake(x + dx * w, y + dy * w, width * w, height * w);
    };
    oval(c, at(-1.0, 0.737, 2.0, 1.474), shirt[0], shirt[1], shirt[2]);    // shoulders
    paint(c, at(-0.21, 0.5, 0.42, 0.526), 0.85, 0.65, 0.52);               // neck
    oval(c, at(-0.605, -0.948, 1.21, 1.58), 0.22, 0.14, 0.08);             // hair
    oval(c, at(-0.5, -0.684, 1.0, 1.368), 0.92, 0.74, 0.62);               // face
    for (int side = 0; side < 2; side++) {
        CGFloat dx = side * 0.421;
        paint(c, at(-0.329 + dx, -0.305, 0.237, 0.042), 0.25, 0.16, 0.10);   // brow
        oval(c, at(-0.316 + dx, -0.224, 0.21, 0.105), 1, 1, 1);               // eye
        oval(c, at(-0.25 + dx, -0.216, 0.089, 0.089), 0.25, 0.18, 0.12);
        oval(c, at(-0.226 + dx, -0.192, 0.042, 0.042), 0.02, 0.02, 0.02);
    }
    oval(c, at(-0.058, 0.095, 0.116, 0.063), 0.75, 0.55, 0.45);             // nose
    oval(c, at(-0.184, 0.303, 0.368, 0.132), 0.70, 0.30, 0.30);             // mouth
    oval(c, at(-0.158, 0.329, 0.316, 0.053), 0.45, 0.12, 0.14);
}

// Without softening by about 1.6% of the side Vision sees no face in flat shapes.
static UIImage *softened(UIImage *flat) {
    CIImage *soft = [[[CIImage imageWithCGImage:flat.CGImage] imageByClampingToExtent] imageByApplyingGaussianBlurWithSigma:kPhotoSide * 0.016];
    CGImageRef image = [[CIContext contextWithOptions:nil] createCGImage:soft fromRect:CGRectMake(0, 0, kPhotoSide, kPhotoSide)];
    UIImage *result = [UIImage imageWithCGImage:image];
    CGImageRelease(image);
    return result;
}

// Teal behind a face cut by the bottom edge under its mouth, so that the box Vision finds for it reaches the edge: the
// foot is the face in the middle and teal either side.
static const CGFloat kTeal[3] = {0.08, 0.42, 0.48};
static UIImage *faceAtBottomPhoto(void) {
    return softened(photo(^(CGContextRef c, CGFloat side) {
        CGFloat top[3] = {0.12, 0.50, 0.56};
        verticalGradient(c, side, top, kTeal);
        person(c, side / 2, side * 0.78, side * 0.46, kTeal);
    }));
}

// A large face in the middle on warm gray, in a deep blue shirt along the foot.
static const CGFloat kShirt[3] = {0.12, 0.20, 0.55};
static UIImage *largeFacePhoto(void) {
    return softened(photo(^(CGContextRef c, CGFloat side) {
        CGFloat top[3] = {0.62, 0.58, 0.54}, bottom[3] = {0.48, 0.45, 0.42};
        verticalGradient(c, side, top, bottom);
        person(c, side / 2, side * 0.40, side * 0.46, kShirt);
    }));
}

// No one: a sky, dark hills, and green grass along the foot.
static const CGFloat kGrass[3] = {0.20, 0.55, 0.28};
static UIImage *noFacePhoto(void) {
    return photo(^(CGContextRef c, CGFloat side) {
        CGFloat top[3] = {0.35, 0.55, 0.85}, bottom[3] = {0.80, 0.86, 0.95};
        verticalGradient(c, side, top, bottom);
        paint(c, CGRectMake(0, side * 0.62, side, side * 0.18), 0.18, 0.24, 0.32);
        paint(c, CGRectMake(0, side * 0.80, side, side * 0.20), kGrass[0], kGrass[1], kGrass[2]);
    });
}

// A dark stage: near black, a dim violet light from the top, and a figure in the dark.
static UIImage *darkPhoto(void) {
    return softened(photo(^(CGContextRef c, CGFloat side) {
        CGFloat top[3] = {0.22, 0.10, 0.32}, bottom[3] = {0.03, 0.02, 0.05};
        verticalGradient(c, side, top, bottom);
        oval(c, CGRectMake(side * 0.36, side * 0.30, side * 0.28, side * 0.34), 0.10, 0.07, 0.10);
        oval(c, CGRectMake(side * 0.22, side * 0.58, side * 0.56, side * 0.60), 0.06, 0.04, 0.08);
        paint(c, CGRectMake(0, side * 0.86, side, side * 0.14), 0.14, 0.05, 0.20);
    }));
}

// Flat, for the reading's own rules with the faces given: teal above, a skin-coloured oval in the middle of the foot
// whose box is `kGivenFootFace`, nothing else.
static const CGRect kGivenFootFace = {{0.3, 0.7}, {0.4, 0.3}};
static const CGFloat kSkin[3] = {0.92, 0.74, 0.62};
static UIImage *givenFaceAtBottomPhoto(void) {
    return photo(^(CGContextRef c, CGFloat side) {
        paint(c, CGRectMake(0, 0, side, side), kTeal[0], kTeal[1], kTeal[2]);
        oval(c, CGRectMake(side * kGivenFootFace.origin.x, side * kGivenFootFace.origin.y, side * kGivenFootFace.size.width,
                           side * kGivenFootFace.size.height), kSkin[0], kSkin[1], kSkin[2]);
    });
}

// Blue above a golden foot, its hue in the skin and yellow band.
static const CGFloat kGold[3] = {0.85, 0.68, 0.12};
static UIImage *goldFootPhoto(void) {
    return photo(^(CGContextRef c, CGFloat side) {
        paint(c, CGRectMake(0, 0, side, side), 0.20, 0.30, 0.60);
        paint(c, CGRectMake(0, side * 0.80, side, side * 0.20), kGold[0], kGold[1], kGold[2]);
    });
}

// Blue above a muted blue-gray foot, its chroma under 0.06.
static const CGFloat kMuted[3] = {0.38, 0.44, 0.54};
static UIImage *mutedFootPhoto(void) {
    return photo(^(CGContextRef c, CGFloat side) {
        paint(c, CGRectMake(0, 0, side, side), 0.20, 0.30, 0.60);
        paint(c, CGRectMake(0, side * 0.80, side, side * 0.20), kMuted[0], kMuted[1], kMuted[2]);
    });
}

// `base` with a mark of `n` pixels in its top left corner, away from the foot: another picture to read, so not the
// reading the cache keeps for `base`.
static UIImage *variant(UIImage *base, NSUInteger n) {
    return photo(^(CGContextRef c, CGFloat side) {
        [base drawInRect:CGRectMake(0, 0, side, side)];
        paint(c, CGRectMake(0, 0, 8 * n, 8), 1, 0, 1);
    });
}

// The teal foot of givenFaceAtBottomPhoto split down the middle, teal and red: a face over all of the foot leaves
// nothing outside it, and the whole foot is its colour.
static UIImage *splitFootPhoto(void) {
    return photo(^(CGContextRef c, CGFloat side) {
        paint(c, CGRectMake(0, 0, side, side), kTeal[0], kTeal[1], kTeal[2]);
        paint(c, CGRectMake(side / 2, side * 0.75, side / 2, side * 0.25), 0.80, 0.15, 0.15);
    });
}
