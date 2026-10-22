// Shared CPU-only fallback renderer for lock-screen artwork and PiP. Snapshot preferences on the
// caller's state thread, then render off-main. Returned images are cached by source/style/raster size.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdint.h>

typedef NS_ENUM(NSInteger, SGLyricsBackgroundMode) {
    SGLyricsBackgroundCover = 0,
    SGLyricsBackgroundMonochrome = 1,
    SGLyricsBackgroundBlur = 2,
    SGLyricsBackgroundGradient = 3,
    SGLyricsBackgroundSolid = 4,
};
typedef struct {
    SGLyricsBackgroundMode mode;
    CGFloat darkness;
    CGFloat blur;
    uint32_t color;
} SGLyricsBackgroundStyle;

// Keys: prefix + .mode/.darkness/.blur/.color. Darkness is stored as percent, returned as 0...0.85.
// Defaults: Cover, 45%, blur 20 (pixels at width 640), RGB 0x18181B. Reads never write preferences.
SGLyricsBackgroundStyle SGLyricsBackgroundRead(NSString *prefix);
// Includes every normalized field and a rendering revision; suitable for disk and preview cache keys.
NSString *SGLyricsBackgroundIdentity(SGLyricsBackgroundStyle style);
CGImageRef SGLyricsBackgroundCreate(CGImageRef cover, CGSize size, SGLyricsBackgroundStyle style) CF_RETURNS_RETAINED;
