// The same bounded CPU renderer is used by PiP, the settings preview, driver and Mac harness.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "LyricsPiPStyle.h"
#import "Shared/LyricsBackground/LyricsBackground.h"

typedef struct {
    CGFloat size;
    NSUInteger lines;
    BOOL truncated;
} SGLyricsPiPTextFit;

// How `text` is laid out in a box: the font size used, how many lines are drawn, and whether it
// was cut with "…". The largest whole-point size in [minSize, size] that fits height wins; below
// minSize the text is drawn at minSize with its last line truncated.
SGLyricsPiPTextFit SGLyricsPiPFitText(NSString *text, CGSize box, CGFloat size, CGFloat minSize);

// The same frame as PNG data (BGRA premultiplied-first little-endian, device RGB, as the PiP pixel buffers are).
NSData *SGLyricsPiPFramePNG(NSArray<NSString *> *content);

// Content retains its original first three slots: current, next, credit; then pronunciation,
// translation, song, artist. All rectangles use bottom-left raster coordinates.
NSArray<NSValue *> *SGLyricsPiPFrameRects(NSArray<NSString *> *content, SGLyricsPiPStyle *style);
SGLyricsPiPTextFit SGLyricsPiPFitRole(NSString *text, CGSize box, SGLyricsPiPStyle *style, NSUInteger role);
void SGLyricsPiPDrawStyledFrame(CGContextRef context, NSArray<NSString *> *content,
    SGLyricsPiPStyle *style, CGImageRef background, CGImageRef cover);
NSData *SGLyricsPiPStyledPNG(NSArray<NSString *> *content, SGLyricsPiPStyle *style, CGImageRef cover);
// The PiP background preferences, read once into a value a render can use on any thread.
SGLyricsBackgroundStyle SGLyricsPiPReadBackground(void);
// The frame itself, without the PNG round trip. Takes only values (`style`, `background` from the caller's
// snapshot), so it can run off main; the caller owns the returned image.
CGImageRef SGLyricsPiPCreateStyledImage(NSArray<NSString *> *content, SGLyricsPiPStyle *style, CGImageRef cover,
    SGLyricsBackgroundStyle background) CF_RETURNS_RETAINED;
