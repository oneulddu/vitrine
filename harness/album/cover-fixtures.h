// The covers the picture-aware cover is checked on (cover-read-check.m, cover-hero-check.m) and shown with (main.m's
// `cover` run), drawn in code at 600 x 600: each picture is the kind of cover named, nothing read from disk.
#import <CoreImage/CoreImage.h>
#import <UIKit/UIKit.h>

static const CGFloat kFixtureSide = 600;
// A gradient carried past its ends, so the whole picture is opaque.
static const CGGradientDrawingOptions kGradientCovers = kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation;

static UIImage *fixture(void (^draw)(CGContextRef c, CGFloat side)) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(kFixtureSide, kFixtureSide) format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) { draw(context.CGContext, kFixtureSide); }];
}

static void fill(CGContextRef c, CGRect rect, CGFloat r, CGFloat g, CGFloat b) {
    CGContextSetRGBFillColor(c, r, g, b, 1);
    CGContextFillRect(c, rect);
}

// Art for the middle of a flat sleeve: four coloured bars on a dark plate.
static void centredArt(CGContextRef c, CGRect rect) {
    fill(c, rect, 0.10, 0.12, 0.30);
    CGFloat bar = rect.size.width / 4;
    CGFloat colours[4][3] = {{0.95, 0.30, 0.20}, {0.95, 0.80, 0.20}, {0.20, 0.75, 0.55}, {0.40, 0.45, 0.95}};
    for (int i = 0; i < 4; i++) {
        fill(c, CGRectMake(rect.origin.x + i * bar + bar * 0.15, rect.origin.y + rect.size.height * 0.15, bar * 0.7,
                           rect.size.height * 0.7), colours[i][0], colours[i][1], colours[i][2]);
    }
}

// A flat border with art covering `share` of the side, centred.
static UIImage *flatSleeve(CGFloat r, CGFloat g, CGFloat b, CGFloat share) {
    return fixture(^(CGContextRef c, CGFloat side) {
        fill(c, CGRectMake(0, 0, side, side), r, g, b);
        CGFloat art = side * share;
        centredArt(c, CGRectMake((side - art) / 2, (side - art) / 2, art, art));
    });
}

static UIImage *solidDarkCover(void) { return flatSleeve(0.07, 0.07, 0.07, 0.6); }
static UIImage *solidLightCover(void) { return flatSleeve(0.96, 0.96, 0.95, 0.6); }
static UIImage *solidRedCover(void) { return flatSleeve(0.78, 0.12, 0.12, 0.6); }
// The same sleeve with the art over 72% of the side: under 55% of it left flat, so not solid.
static UIImage *largeArtCover(void) { return flatSleeve(0.07, 0.07, 0.07, 0.72); }
// A flat dark border broken along 8% of it by a mark on the left edge: still solid.
static UIImage *markedSleeveCover(void) {
    return fixture(^(CGContextRef c, CGFloat side) {
        fill(c, CGRectMake(0, 0, side, side), 0.07, 0.07, 0.07);
        centredArt(c, CGRectMake(side * 0.2, side * 0.2, side * 0.6, side * 0.6));
        fill(c, CGRectMake(0, side * 0.3, side * 3 / 64, side * 20 / 64), 0.9, 0.85, 0.2);
    });
}

// Near black with a small bright logo in the middle.
static UIImage *tinyLogoCover(void) {
    return fixture(^(CGContextRef c, CGFloat side) {
        fill(c, CGRectMake(0, 0, side, side), 0.04, 0.04, 0.05);
        fill(c, CGRectMake(side * 0.45, side * 0.47, side * 0.1, side * 0.06), 1, 1, 1);
    });
}

// Dark, unevenly lit, with a large orange disc over about a fifth of it.
static UIImage *darkAccentCover(void) {
    return fixture(^(CGContextRef c, CGFloat side) {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat stops[] = {0.02, 0.03, 0.08, 1, 0.16, 0.10, 0.20, 1};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, stops, NULL, 2);
        CGContextDrawLinearGradient(c, gradient, CGPointZero, CGPointMake(side * 0.3, side), kGradientCovers);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        CGContextSetRGBFillColor(c, 0.95, 0.50, 0.10, 1);
        CGFloat d = side * 0.52;
        CGContextFillEllipseInRect(c, CGRectMake(side * 0.42, side * 0.12, d, d));
    });
}

// A face over a sky, from under the top down through the foot and wider than half of it, with green grass along the
// foot on either side; what Vision is told it finds there.
static const CGRect kPortraitFace = {{0.2, 0.3}, {0.6, 0.7}};
static UIImage *portraitCover(void) {
    return fixture(^(CGContextRef c, CGFloat side) {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat stops[] = {0.55, 0.75, 0.95, 1, 0.80, 0.88, 0.97, 1};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, stops, NULL, 2);
        CGContextDrawLinearGradient(c, gradient, CGPointZero, CGPointMake(0, side), kGradientCovers);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        fill(c, CGRectMake(0, side * 0.80, side, side * 0.20), 0.22, 0.62, 0.25);
        fill(c, CGRectMake(side * kPortraitFace.origin.x, side * kPortraitFace.origin.y, side * kPortraitFace.size.width,
                           side * kPortraitFace.size.height), 0.90, 0.70, 0.58);
    });
}

// A face Vision itself finds (no answer given for it): drawn in flat shapes, head and shoulders on a sky, then softened
// by a blur of kFaceSoftening of the side, without which Vision sees no face in it. Its lowest edge is about 60% down.
static const CGFloat kFaceSoftening = 0.016;
static void faceEllipse(CGContextRef c, CGFloat x, CGFloat y, CGFloat w, CGFloat h, CGFloat r, CGFloat g, CGFloat b) {
    CGContextSetRGBFillColor(c, r, g, b, 1);
    CGContextFillEllipseInRect(c, CGRectMake(x, y, w, h));
}
static UIImage *faceCover(void) {
    UIImage *flat = fixture(^(CGContextRef c, CGFloat side) {
        // Drawn in a 1000 square from the bottom up.
        CGContextTranslateCTM(c, 0, side);
        CGContextScaleCTM(c, side / 1000, -side / 1000);
        fill(c, CGRectMake(0, 0, 1000, 1000), 0.55, 0.72, 0.92);
        faceEllipse(c, 120, -300, 760, 560, 0.20, 0.25, 0.45);         // shoulders
        fill(c, CGRectMake(420, 150, 160, 200), 0.85, 0.65, 0.52);      // neck
        faceEllipse(c, 270, 300, 460, 600, 0.22, 0.14, 0.08);           // hair
        faceEllipse(c, 310, 280, 380, 520, 0.92, 0.74, 0.62);           // face
        fill(c, CGRectMake(375, 640, 90, 16), 0.25, 0.16, 0.10);        // brows
        fill(c, CGRectMake(535, 640, 90, 16), 0.25, 0.16, 0.10);
        for (int eye = 0; eye < 2; eye++) {
            CGFloat x = 380 + eye * 160;
            faceEllipse(c, x, 585, 80, 40, 1, 1, 1);
            faceEllipse(c, x + 25, 588, 34, 34, 0.25, 0.18, 0.12);
            faceEllipse(c, x + 34, 597, 16, 16, 0.02, 0.02, 0.02);
        }
        faceEllipse(c, 478, 480, 44, 24, 0.75, 0.55, 0.45);             // nose
        faceEllipse(c, 430, 375, 140, 50, 0.70, 0.30, 0.30);            // mouth
        faceEllipse(c, 440, 395, 120, 20, 0.45, 0.12, 0.14);
    });
    CIImage *soft = [[[CIImage imageWithCGImage:flat.CGImage] imageByClampingToExtent] imageByApplyingGaussianBlurWithSigma:kFixtureSide * kFaceSoftening];
    CGImageRef image = [[CIContext contextWithOptions:nil] createCGImage:soft fromRect:CGRectMake(0, 0, kFixtureSide, kFixtureSide)];
    UIImage *cover = [UIImage imageWithCGImage:image];
    CGImageRelease(image);
    return cover;
}

// A scanned sleeve: a dark blue gradient with pale bars, and the scanner's pale border along the bottom, a hard edge
// under the title (main.m's sleeve, drawn in a 300 square).
static void drawScannedSleeve(CGContextRef c, CGFloat side) {
    CGContextScaleCTM(c, side / 300, side / 300);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat components[] = {0.16, 0.34, 0.62, 1, 0.07, 0.10, 0.22, 1};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, components, NULL, 2);
    CGContextDrawLinearGradient(c, gradient, CGPointZero, CGPointMake(300, 300), 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(c, 1, 1, 1, 0.30);
    for (int i = 0; i < 4; i++) CGContextFillRect(c, CGRectMake(24 + i * 62, 60 + (i % 2) * 90, 48, 150));
    CGContextSetRGBFillColor(c, 0.82, 0.82, 0.82, 1);
    CGContextFillRect(c, CGRectMake(0, 282, 300, 18));
}
static UIImage *scannedSleeveCover(void) { return fixture(^(CGContextRef c, CGFloat side) { drawScannedSleeve(c, side); }); }

// Colourful bands, magenta the widest.
static UIImage *colourfulCover(void) {
    return fixture(^(CGContextRef c, CGFloat side) {
        fill(c, CGRectMake(0, 0, side * 0.45, side), 0.85, 0.10, 0.75);
        fill(c, CGRectMake(side * 0.45, 0, side * 0.20, side), 0.95, 0.85, 0.10);
        fill(c, CGRectMake(side * 0.65, 0, side * 0.20, side), 0.10, 0.80, 0.85);
        fill(c, CGRectMake(side * 0.85, 0, side * 0.15, side), 0.15, 0.20, 0.85);
    });
}

static UIImage *transparentCover(void) {
    return fixture(^(CGContextRef c, CGFloat side) {});
}
