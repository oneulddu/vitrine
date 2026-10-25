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

// The lock screen's prefix, whose default is the cover blurred to soft colour fields.
#define SGLyricsBackgroundLockScreen @"spotifyglass.lockscreen.background"
// Blur runs from 0 to this, in pixels at width 640.
#define SGLyricsBackgroundMaxBlur 100

// Keys: prefix + .mode/.darkness/.blur/.color. Darkness is stored as percent, returned as 0...0.85.
// Defaults (SGLyricsBackgroundDefault): Cover, 45%, blur 20, RGB 0x18181B; the lock screen's prefix
// Blur at 60 instead. A value the user stored is kept as it is. Reads never write preferences.
SGLyricsBackgroundStyle SGLyricsBackgroundDefault(NSString *prefix);
SGLyricsBackgroundStyle SGLyricsBackgroundRead(NSString *prefix);
// Includes every normalized field and a rendering revision; suitable for disk and preview cache keys.
NSString *SGLyricsBackgroundIdentity(SGLyricsBackgroundStyle style);
CGImageRef SGLyricsBackgroundCreate(CGImageRef cover, CGSize size, SGLyricsBackgroundStyle style) CF_RETURNS_RETAINED;
