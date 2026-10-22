// A lyric-free breathing clip of an already rendered selected background. The historical Fluid entry
// points now share SGLyricsClip's CPU drawing/encoder; no separate moving-blur renderer remains.
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

// The first frame. `cover` is a full-resolution, already styled backdrop, not the raw album image.
CGImageRef SGFluidClipFrame(CGImageRef cover, CGSize size) CF_RETURNS_RETAINED;
// Writes a seamless 4 s / 15 fps breathing loop as H.264. NULL backdrop returns NO.
BOOL SGFluidClipWrite(NSURL *file, CGImageRef cover, CGSize size);
