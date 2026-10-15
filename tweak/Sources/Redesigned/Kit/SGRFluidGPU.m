#import <Metal/Metal.h>
#import <UIKit/UIKit.h>
#import <simd/simd.h>
#import "Core/SGCore.h"
#import "SGRFluidGPU.h"
#import "SGRTokens.h"

// How long a new cover takes to run in. Under Reduce Motion it fades over SGRCrossfade instead.
static const CFTimeInterval kRunIn = 1.4;

// In the shader's order and layout (a float4 first, so both sides pad the same way).
typedef struct {
    simd_float4 visible;   // the visible rect as shares of the layer: x, y, width, height
    simd_float2 aspect;    // the visible rect's sides as shares of its longer side
    float time;            // the flow's clock, in seconds at the standard speed
    float warp;            // the Warp setting as a factor
    float progress;        // how far the new cover has run in, 0 to 1
    float flows;           // 1 while it runs in flowing, 0 while it fades
} Uniforms;

// ZOOM: the visible rect's longer side reads this share of the cover, about what the Light renderer's copies,
// twice the screen's size and more, show of theirs.
static NSString *const kShader = @"#include <metal_stdlib>\n"
"using namespace metal;\n"
"#define ZOOM 0.55\n"
"struct U { float4 visible; float2 aspect; float time; float warp; float progress; float flows; };\n"
"struct V { float4 position [[position]]; float2 uv; };\n"
// One triangle past the corners covers the drawable; uv runs 0 to 1 down and across it.
"vertex V fluidVertex(uint id [[vertex_id]]) {\n"
"    float2 p = float2((id << 1) & 2, id & 2);\n"
"    V v;\n"
"    v.position = float4(p * 2.0 - 1.0, 0.0, 1.0);\n"
"    v.uv = float2(p.x, 1.0 - p.y);\n"
"    return v;\n"
"}\n"
// A cubic B-spline from four bilinear reads: no grid of texels shows on a 128 px picture blown up to the screen.
"static float4 smoothRead(texture2d<float> t, sampler s, float2 uv) {\n"
"    float2 size = float2(t.get_width(), t.get_height());\n"
"    float2 st = uv * size - 0.5;\n"
"    float2 i = floor(st), f = st - i, f2 = f * f, f3 = f2 * f;\n"
"    float2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) / 6.0;\n"
"    float2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0;\n"
"    float2 w2 = (1.0 + 3.0 * f + 3.0 * f2 - 3.0 * f3) / 6.0;\n"
"    float2 w3 = f3 / 6.0;\n"
"    float2 g0 = w0 + w1, g1 = w2 + w3;\n"
"    float2 h0 = (i - 0.5 + w1 / g0) / size, h1 = (i + 1.5 + w3 / g1) / size;\n"
"    return g0.y * (g0.x * t.sample(s, float2(h0.x, h0.y)) + g1.x * t.sample(s, float2(h1.x, h0.y)))\n"
"         + g1.y * (g0.x * t.sample(s, float2(h0.x, h1.y)) + g1.x * t.sample(s, float2(h1.x, h1.y)));\n"
"}\n"
// Where a point of the screen reads the cover at time t: three bends along a slowly changing field, each
// taking the last one's result, then a slow turn of the whole. Warp scales the bends.
"static float2 flowAt(float2 q, float t, float w) {\n"
"    q += w * 0.16 * float2(sin(q.y * 2.3 + t * 0.31), sin(q.x * 2.1 - t * 0.27 + 1.3));\n"
"    q += w * 0.10 * float2(sin(q.y * 3.7 - t * 0.23 + 2.1), sin(q.x * 3.3 + t * 0.19 + 0.4));\n"
"    q += w * 0.06 * float2(sin((q.x + q.y) * 5.1 + t * 0.17), sin((q.x - q.y) * 4.7 - t * 0.21 + 3.0));\n"
"    float a = t * 0.04, c = cos(a), s = sin(a);\n"
"    return float2(c * q.x - s * q.y, s * q.x + c * q.y);\n"
"}\n"
"fragment float4 fluidFragment(V in [[stage_in]], constant U &u [[buffer(0)]],\n"
"                              texture2d<float> from [[texture(0)]], texture2d<float> to [[texture(1)]],\n"
"                              sampler s [[sampler(0)]]) {\n"
"    float2 p = (in.uv - u.visible.xy) / u.visible.zw;\n"
"    float2 q = (p - 0.5) * u.aspect;\n"
"    float2 r = flowAt(q, u.time, u.warp);\n"
// The new cover reaches first where a slow wave is low, and the old one is swept aside as it goes.
"    float wave = 0.5 + 0.5 * sin(q.x * 3.1 + q.y * 2.3 + sin(q.y * 4.0 + u.time * 0.5));\n"
"    float m = u.flows > 0.5 ? smoothstep(0.0, 1.0, saturate(u.progress * 1.5 - wave * 0.5)) : u.progress;\n"
"    float2 bend = 0.22 * u.flows * float2(sin(q.y * 2.9 + 0.7), cos(q.x * 2.6 + 1.9));\n"
"    float4 a = smoothRead(from, s, (r + bend * u.progress) * ZOOM + 0.5);\n"
"    float4 b = smoothRead(to, s, (r - bend * (1.0 - u.progress)) * ZOOM + 0.5);\n"
"    float3 c = mix(a.rgb, b.rgb, m);\n"
// Half a step of noise against the banding a slow gradient shows in eight bits.
"    uint2 ip = uint2(in.position.xy);\n"
"    uint h = ip.x * 1973u + ip.y * 9277u;\n"
"    h = (h ^ (h >> 13)) * 1274126177u;\n"
"    h ^= h >> 16;\n"
"    float noise = float(h & 0xffffu) / 65535.0 - 0.5;\n"
"    return float4(c + noise / 255.0, 1.0);\n"
"}\n";

BOOL SGRFluidGPUAvailable(void) {
    static BOOL available;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ available = MTLCreateSystemDefaultDevice() != nil; });
    return available;
}

// What every layer shares, made once on the main thread; the shader compiles off it.
static id<MTLDevice> sDevice;
static id<MTLCommandQueue> sQueue;
static id<MTLRenderPipelineState> sPipeline;
static id<MTLSamplerState> sSampler;
static BOOL sFailed;
static NSMutableArray<void (^)(void)> *sWaiting;

static void finish(id<MTLRenderPipelineState> pipeline, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray<void (^)(void)> *waiting = sWaiting;
        sWaiting = nil;
        if (!pipeline) {
            sFailed = YES;
            SGLog(@"redesign kit: the Smooth fluid shader failed, Light stays: %@", error.localizedDescription ?: @"no reason");
            return;
        }
        sPipeline = pipeline;
        for (void (^ready)(void) in waiting) ready();
    });
}

// Runs the block on the main thread once the pipeline exists: at once if it does, never if it failed.
static void whenReady(void (^ready)(void)) {
    if (sPipeline) { ready(); return; }
    if (sFailed) return;
    if (sWaiting) { [sWaiting addObject:ready]; return; }
    sWaiting = [NSMutableArray arrayWithObject:ready];
    sDevice = MTLCreateSystemDefaultDevice();
    sQueue = [sDevice newCommandQueue];
    if (!sDevice || !sQueue) { finish(nil, nil); return; }
    MTLSamplerDescriptor *sampling = [MTLSamplerDescriptor new];
    sampling.minFilter = MTLSamplerMinMagFilterLinear;
    sampling.magFilter = MTLSamplerMinMagFilterLinear;
    // Mirrored, so a bend that reads past the cover's edge finds more of the cover rather than a smear.
    sampling.sAddressMode = MTLSamplerAddressModeMirrorRepeat;
    sampling.tAddressMode = MTLSamplerAddressModeMirrorRepeat;
    sSampler = [sDevice newSamplerStateWithDescriptor:sampling];
    id<MTLDevice> device = sDevice;
    [device newLibraryWithSource:kShader options:nil completionHandler:^(id<MTLLibrary> library, NSError *error) {
        if (!library) { finish(nil, error); return; }
        MTLRenderPipelineDescriptor *described = [MTLRenderPipelineDescriptor new];
        described.vertexFunction = [library newFunctionWithName:@"fluidVertex"];
        described.fragmentFunction = [library newFunctionWithName:@"fluidFragment"];
        described.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        [device newRenderPipelineStateWithDescriptor:described completionHandler:^(id<MTLRenderPipelineState> pipeline, NSError *failure) {
            finish(pipeline, failure);
        }];
    }];
}

// The picture as a texture, in sRGB's numbers as they are (the shader mixes them the way Core Animation's
// crossfade does).
static id<MTLTexture> textureOf(id picture) {
    CGImageRef image = (__bridge CGImageRef)picture;
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    if (!sDevice || width == 0 || height == 0) return nil;
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef bitmap = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space,
                                                kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!bitmap) return nil;
    CGContextDrawImage(bitmap, CGRectMake(0, 0, width, height), image);
    MTLTextureDescriptor *described = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                         width:width height:height mipmapped:NO];
    described.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> texture = [sDevice newTextureWithDescriptor:described];
    [texture replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0
                 withBytes:CGBitmapContextGetData(bitmap) bytesPerRow:width * 4];
    CGContextRelease(bitmap);
    return texture;
}

// A suspended app may not use the GPU; a locked phone with Spotify in front is inactive and may.
static BOOL mayDraw(void) {
    return UIApplication.sharedApplication.applicationState != UIApplicationStateBackground;
}

@interface SGRFluidGPULayer ()
- (void)tick:(CADisplayLink *)link;
@end

// The display link's target, so the link (which retains it) does not keep the layer.
@interface SGRFluidTicker : NSObject
@property (nonatomic, weak) SGRFluidGPULayer *layer;
@end

@implementation SGRFluidTicker
- (void)tick:(CADisplayLink *)link {
    [self.layer tick:link];
}
@end

@implementation SGRFluidGPULayer {
    id _fromPicture, _toPicture;   // CGImages
    id<MTLTexture> _from, _to;     // made from them when first drawn
    float _progress;               // 1 when nothing runs in
    BOOL _flows;
    CFTimeInterval _length, _last;
    double _time;
    CADisplayLink *_link;
    BOOL _ready, _dirty, _drewOnce, _firstPending;
    int _misses;   // ticks in a row whose frame could not be drawn, once nothing else keeps the link
    int _firstFailures;   // first frames the GPU failed; after three, Light stays and none is tried again
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _rate = 1;
    _warp = 1;
    _progress = 1;
    self.pixelFormat = MTLPixelFormatBGRA8Unorm;
    self.framebufferOnly = YES;
    self.opaque = YES;
    self.contentsScale = 1;
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    self.colorspace = space;
    CGColorSpaceRelease(space);
    NSNull *off = NSNull.null;
    self.actions = @{@"bounds": off, @"position": off, @"frame": off, @"contents": off, @"hidden": off};
    __weak SGRFluidGPULayer *weakSelf = self;
    whenReady(^{
        SGRFluidGPULayer *layer = weakSelf;
        if (!layer) return;
        layer.device = sDevice;
        layer->_ready = YES;
        [layer update];
    });
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(update)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    return self;
}

- (void)dealloc {
    [_link invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - what it shows

- (void)setPicture:(CGImageRef)picture animated:(BOOL)animated {
    if (!picture) return;
    if (animated && _toPicture && _drewOnce && !_held && mayDraw()) {
        // One still running in is cut short: the new one runs in over the one it was bringing.
        _fromPicture = _toPicture;
        _from = _to;
        // Held still (paused, Low Power Mode, Reduce Motion) it fades over the Light renderer's time, a few
        // frames, rather than flowing for longer.
        _flows = _moving && !SGRReduceMotion();
        _length = _flows ? kRunIn : SGRCrossfade;
        _progress = 0;
    } else {
        _fromPicture = nil;
        _from = nil;
        _progress = 1;
    }
    _toPicture = (__bridge id)picture;
    _to = nil;
    _dirty = YES;
    [self update];
}

- (void)setMoving:(BOOL)moving {
    if (moving == _moving) return;
    _moving = moving;
    [self update];
}

- (void)setHeld:(BOOL)held {
    if (held == _held) return;
    _held = held;
    [self update];
}

- (void)setWarp:(float)warp {
    if (warp == _warp) return;
    _warp = warp;
    _dirty = YES;
    [self update];
}

- (void)setVisibleRect:(CGRect)rect {
    if (CGRectEqualToRect(rect, _visibleRect)) return;
    _visibleRect = rect;
    _dirty = YES;
    [self update];
}

- (void)setBounds:(CGRect)bounds {
    [super setBounds:bounds];
    [self fit];
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    [self fit];
}

- (void)layoutSublayers {
    [super layoutSublayers];
    [self fit];
}

- (void)fit {
    CGSize bounds = self.bounds.size;
    CGSize size = CGSizeMake(MAX(1, round(bounds.width * self.contentsScale)), MAX(1, round(bounds.height * self.contentsScale)));
    if (CGSizeEqualToSize(size, self.drawableSize)) return;
    self.drawableSize = size;
    _dirty = YES;
    [self update];
}

#pragma mark - drawing

// Ticks while it flows or a cover runs in; otherwise a change waiting to be seen is drawn once.
- (void)update {
    BOOL wants = _ready && !_held && (_moving || _progress < 1) && mayDraw() && _firstFailures < 3;
    if (wants && !_link) {
        SGRFluidTicker *ticker = [SGRFluidTicker new];
        ticker.layer = self;
        _link = [CADisplayLink displayLinkWithTarget:ticker selector:@selector(tick:)];
        _link.preferredFrameRateRange = CAFrameRateRangeMake(15, 30, 30);
        _last = 0;
        [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    } else if (!wants && _link) {
        [_link invalidate];
        _link = nil;
    }
    if (_dirty && !_link) [self draw];
}

- (void)tick:(CADisplayLink *)link {
    CFTimeInterval now = link.timestamp;
    CFTimeInterval step = _last > 0 ? MIN(0.1, now - _last) : 0;
    _last = now;
    if (_moving) _time += step * _rate;
    if (_progress < 1) {
        _progress = (float)MIN(1.0, _progress + step / MAX(0.05, _length));
        if (_progress >= 1) {
            _fromPicture = nil;
            _from = nil;
        }
    }
    _dirty = YES;
    BOOL drew = [self draw];
    if (_moving || _progress < 1) return;
    // The last frame of a running-in is tried again for a moment if no drawable was free, rather than left half mixed.
    if (!drew && ++_misses < 30) return;
    _misses = 0;
    [self update];
}

- (BOOL)draw {
    if (!_ready || _held || !_toPicture || !mayDraw() || _firstFailures >= 3) return NO;
    CGRect bounds = self.bounds;
    if (bounds.size.width < 1 || bounds.size.height < 1) return NO;
    if (!_to) _to = textureOf(_toPicture);
    if (_fromPicture && !_from) _from = textureOf(_fromPicture);
    if (!_to) return NO;
    id<CAMetalDrawable> drawable = [self nextDrawable];
    if (!drawable) return NO;

    CGRect visible = CGRectIsEmpty(_visibleRect) ? bounds : _visibleRect;
    CGFloat longer = MAX(1, MAX(visible.size.width, visible.size.height));
    Uniforms uniforms = {
        .visible = simd_make_float4((float)((visible.origin.x - bounds.origin.x) / bounds.size.width),
                                    (float)((visible.origin.y - bounds.origin.y) / bounds.size.height),
                                    (float)(MAX(1, visible.size.width) / bounds.size.width),
                                    (float)(MAX(1, visible.size.height) / bounds.size.height)),
        .aspect = simd_make_float2((float)(visible.size.width / longer), (float)(visible.size.height / longer)),
        .time = (float)_time,
        .warp = _warp,
        .progress = _from ? _progress : 1,
        .flows = _flows ? 1 : 0,
    };

    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = drawable.texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLCommandBuffer> buffer = [sQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];
    [encoder setRenderPipelineState:sPipeline];
    [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
    [encoder setFragmentTexture:_from ?: _to atIndex:0];
    [encoder setFragmentTexture:_to atIndex:1];
    [encoder setFragmentSamplerState:sSampler atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];
    if (!_drewOnce && !_firstPending && _firstFailures < 3) {
        _firstPending = YES;
        // Settled once the GPU has finished it and a frame or so later, when it is on screen: the layer lies under
        // the copies, so going a little late shows nothing missing, and going early would show the black under
        // both. A frame the GPU failed leaves the copies, and the next frame tries again.
        __weak SGRFluidGPULayer *weakSelf = self;
        [buffer addCompletedHandler:^(id<MTLCommandBuffer> done) {
            BOOL completed = done.status == MTLCommandBufferStatusCompleted;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((completed ? 0.1 : 0) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf firstFrameCompleted:completed];
            });
        }];
    }
    [buffer presentDrawable:drawable];
    [buffer commit];
    _dirty = NO;
    return YES;
}

- (void)firstFrameCompleted:(BOOL)completed {
    _firstPending = NO;
    if (_drewOnce) return;
    if (!completed) {
        SGLog(@"redesign kit: Smooth fluid's first frame failed on the GPU (%d), Light stays", ++_firstFailures);
        // Drawn again on the next tick or now; after the third failure update stops the link for good.
        _dirty = YES;
        [self update];
        return;
    }
    _drewOnce = YES;
    SGLog(@"redesign kit: Smooth fluid drew its first frame at %.0fx%.0f", self.drawableSize.width, self.drawableSize.height);
    void (^drawn)(void) = _drawn;
    _drawn = nil;
    if (drawn) drawn();
}

@end
