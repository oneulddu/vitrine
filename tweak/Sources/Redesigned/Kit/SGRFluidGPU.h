// Fluid artwork drawn on the GPU (SGRFluid.h's Smooth renderer): the same blurred cover the Light renderer turns,
// flowing instead, its parts drifting past each other along a slowly changing field, and a new cover running in
// through the old one rather than fading over it.
//
// The picture comes in already blurred, saturated and held under the brightness ceiling (SGRFluid.m's blurred()),
// so the Blur, Saturation and Brightness settings and the contrast with the player's text are the Light renderer's
// own. The shader only moves pixels around and mixes two such pictures, which never makes one brighter: a cubic
// B-spline's weights and the transition's mix are all positive, and sRGB's curve is convex, so every color drawn
// stays under the ceiling. A little noise breaks up the banding a smooth gradient shows in eight bits.
//
// Drawn at one pixel a point (the picture is a blur), at most 30 times a second by a display link that allows
// 120 Hz UI motion. Only while it moves or a new cover runs in, and never in the background or during the
// player's open/close transition. Held, it keeps its last frame and draws
// nothing. The shader compiles once, off the main thread, from source; until it is ready, or if it fails, the
// layer draws nothing and `drawn` is never called, and SGRFluidLayer keeps the Light renderer in its place.
//
// Threading: main thread only.
#import <QuartzCore/QuartzCore.h>

// A Metal device exists (every iPhone the mod runs on; checked so a simulator without one falls back).
BOOL SGRFluidGPUAvailable(void);

@interface SGRFluidGPULayer : CAMetalLayer
// The blurred cover. Animated, the new one runs in through the shown one (a crossfade under Reduce Motion);
// otherwise it replaces it at once.
- (void)setPicture:(CGImageRef)picture animated:(BOOL)animated;
// Flowing, or held still where it is. Off to begin with.
@property (nonatomic) BOOL moving;
// Hidden by its owner: nothing is drawn, not even a running transition, until it is NO again.
@property (nonatomic) BOOL held;
// The Speed and Warp settings as factors (1 is standard; Warp 0 leaves a picture turning, nothing flowing).
@property (nonatomic) float rate, warp;
// As SGRFluidLayer's: the part on screen, in this layer's coordinates. The whole layer while empty.
@property (nonatomic) CGRect visibleRect;
// Called once, after the first frame has been handed to the screen.
@property (nonatomic, copy) void (^drawn)(void);
@end
