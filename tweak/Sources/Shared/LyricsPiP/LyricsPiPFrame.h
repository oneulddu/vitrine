// The lyrics PiP frame's fixed raster, text fitting and drawing, free of UIKit and of the tweak:
// the Mac harness and phone driver also link Shared/LyricsBackground for the default background.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

extern const size_t SGLyricsPiPFrameWidth, SGLyricsPiPFrameHeight;

typedef struct {
    CGFloat size;
    NSUInteger lines;
    BOOL truncated;
} SGLyricsPiPTextFit;

// How `text` is laid out in a box: the font size used, how many lines are drawn, and whether it
// was cut with "…". The largest whole-point size in [minSize, size] that fits height wins; below
// minSize the text is drawn at minSize with its last line truncated.
SGLyricsPiPTextFit SGLyricsPiPFitText(NSString *text, CGSize box, CGFloat size, CGFloat minSize);

// Draws a whole frame (background + the three texts) into a 640x360 bottom-left-origin context.
// content = @[current, next, credit]; empty strings draw nothing.
void SGLyricsPiPDrawFrame(CGContextRef context, NSArray<NSString *> *content);
// Production uses a precomputed background; never blurs or generates gradients on the playback tick.
void SGLyricsPiPDrawFrameWithBackground(CGContextRef context, NSArray<NSString *> *content, CGImageRef background);

// The same frame as PNG data (BGRA premultiplied-first little-endian, device RGB, as the PiP pixel buffers are).
NSData *SGLyricsPiPFramePNG(NSArray<NSString *> *content);
