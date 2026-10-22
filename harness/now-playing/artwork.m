// Production Logos control flow and follower; only sources, rendering and the OS boundary are stubs.
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>
#import "artwork.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/AnimatedArtwork/SGFluidClip.h"
#import "Shared/AnimatedArtwork/SGMotionClip.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
#import "Shared/LockScreenLyrics/SGLyricsClip.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/NowPlayingExtras.h"
#import "Shared/Player/SGLastTrack.h"

typedef void (^Preview)(CGSize, void (^)(UIImage *));
typedef void (^Video)(CGSize, void (^)(NSURL *));
static char idKey, previewKey, videoKey;
static NSArray *supported;
static NSURL *cacheRoot;
static CGSize lastCoverRequest;
static CGRect screenBounds(id self, SEL cmd) { return CGRectMake(0, 0, 32, 48); }

// Exercise the real metadata -> SGShownTrack -> URL loader -> decode boundary, not an
// SGShownTrackArtwork stub. Only the transport is controlled; no network leaves this process.
static NSMutableDictionary<NSString *, NSURLProtocol *> *coverRequests;
static NSUInteger coverLoads;
@interface CoverProtocol : NSURLProtocol
@end
@implementation CoverProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [request.URL.host isEqual:@"cover.invalid"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    dispatch_async(dispatch_get_main_queue(), ^{
        coverLoads++;
        coverRequests[self.request.URL.absoluteString] = self;
    });
}
- (void)stopLoading {}
@end

// Keep Apple's real object and initializer, but retain the supplied handlers so tests can act as the OS.
@interface MPMediaItemAnimatedArtwork (Harness)
- (instancetype)initHarnessWithArtworkID:(NSString *)name previewImageRequestHandler:(Preview)preview
        videoAssetFileURLRequestHandler:(Video)video;
@end
@implementation MPMediaItemAnimatedArtwork (Harness)
- (instancetype)initHarnessWithArtworkID:(NSString *)name previewImageRequestHandler:(Preview)preview
        videoAssetFileURLRequestHandler:(Video)video {
    self = [self initHarnessWithArtworkID:name previewImageRequestHandler:preview videoAssetFileURLRequestHandler:video];
    if (self) {
        objc_setAssociatedObject(self, &idKey, name, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(self, &previewKey, preview, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(self, &videoKey, video, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    return self;
}
@end

@interface NSFileManager (Harness)
- (NSArray *)harnessURLsForDirectory:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)domains;
@end
@implementation NSFileManager (Harness)
- (NSArray *)harnessURLsForDirectory:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)domains {
    if (directory == NSCachesDirectory) return @[cacheRoot];
    return [self harnessURLsForDirectory:directory inDomains:domains];
}
@end

static NSArray *keys(id self, SEL cmd) { return supported ?: @[]; }
__attribute__((constructor)) static void artworkBoundary(void) {
    coverRequests = [NSMutableDictionary dictionary];
    [NSURLProtocol registerClass:CoverProtocol.class];
    char *path = strdup([[NSTemporaryDirectory() stringByAppendingPathComponent:@"vitrine-artwork.XXXXXX"] fileSystemRepresentation]);
    if (!mkdtemp(path)) abort();
    cacheRoot = [NSURL fileURLWithPath:@(path) isDirectory:YES];
    free(path);
    method_exchangeImplementations(class_getInstanceMethod(NSFileManager.class, @selector(URLsForDirectory:inDomains:)),
                                   class_getInstanceMethod(NSFileManager.class, @selector(harnessURLsForDirectory:inDomains:)));
    class_replaceMethod(object_getClass(MPNowPlayingInfoCenter.class), @selector(supportedAnimatedArtworkKeys), (IMP)keys, "@@:");
    Method bounds = class_getInstanceMethod(UIScreen.class, @selector(nativeBounds));
    class_replaceMethod(UIScreen.class, @selector(nativeBounds), (IMP)screenBounds, method_getTypeEncoding(bounds));
    method_exchangeImplementations(class_getInstanceMethod(MPMediaItemAnimatedArtwork.class,
                                       @selector(initWithArtworkID:previewImageRequestHandler:videoAssetFileURLRequestHandler:)),
                                   class_getInstanceMethod(MPMediaItemAnimatedArtwork.class,
                                       @selector(initHarnessWithArtworkID:previewImageRequestHandler:videoAssetFileURLRequestHandler:)));
}

static SGLockArtwork choice;
static NSHashTable *observers;
static SPTPlayerState *state;
static NSInteger position;
static NSUInteger lookups, posters;
static NSURL *sourceFile;
static NSMutableArray *posterCallbacks;
static UIImage *red, *blue;
// Hold one coverless production worker before it renders, without replacing the renderer or
// changing delivery order on main. Guard the gate and preparation counter across both threads.
static NSString *heldPicture;
static dispatch_semaphore_t renderEntered, renderRelease;
static NSUInteger backgroundPreparations;
static BOOL renderGateTimedOut;

static NSUInteger preparations(void) {
    @synchronized (cacheRoot) { return backgroundPreparations; }
}

SGLockArtwork SGLockScreenArtwork(void) { return choice; }
CGFloat SGMotionPixels(void) { return 32; }
NSString *SGURIString(id uri) { return [uri isKindOfClass:NSString.class] ? uri : [uri absoluteString]; }
SPTPlayerState *SGPlayerState(void) { return state; }
NSInteger SGKaraokePositionMs(void) { return position; }
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {
    if (!observers) observers = [NSHashTable weakObjectsHashTable];
    [observers addObject:observer];
}
NSArray *SGMotionSourceOrder(void) { return @[@"canvas"]; }
NSURL *SGMotionCanvasIn(NSDictionary *metadata) { return nil; }
NSString *SGLocalFileCoverInURL(NSString *url) { return nil; }
BOOL SGMotionCanvasOutranks(NSArray *order, NSString *source) { return YES; }
void SGMotionClipFor(NSString *uri, NSURL *canvas, NSString *artist, NSString *album, SGMotionShape shape,
                     CGFloat pixels, void (^done)(NSURL *, NSString *)) {
    lookups++;
    done(sourceFile, sourceFile ? @"canvas" : nil);
}
void SGMotionPoster(NSURL *file, void (^done)(UIImage *)) {
    posters++;
    if (!posterCallbacks) posterCallbacks = [NSMutableArray array];
    [posterCallbacks addObject:[done copy]];
}
NSURL *SGMotionMadeFile(NSString *key) {
    dispatch_semaphore_t entered = nil, release = nil;
    @synchronized (cacheRoot) {
        if ([key hasPrefix:@"background\n"]) backgroundPreparations++;
        if (heldPicture && [key hasPrefix:[NSString stringWithFormat:@"background\n%@\n", heldPicture]]
            && [key hasSuffix:@"\nno-cover"]) {
            entered = renderEntered;
            release = renderRelease;
            heldPicture = nil;
        }
    }
    if (entered) {
        dispatch_semaphore_signal(entered);
        BOOL timedOut = dispatch_semaphore_wait(release, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0;
        @synchronized (cacheRoot) { renderGateTimedOut = timedOut; }
    }
    NSData *data = [key dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, hash);
    NSMutableString *name = [NSMutableString string];
    for (NSUInteger i = 0; i < sizeof(hash); i++) [name appendFormat:@"%02x", hash[i]];
    return [cacheRoot URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"mp4"]];
}

static UIImage *image(UIColor *color) {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(24, 32)] imageWithActions:^(UIGraphicsImageRendererContext *c) {
        [color setFill];
        UIRectFill(CGRectMake(0, 0, 24, 32));
    }];
}
CGSize SGLyricsClipSize(CGFloat pixels) { return CGSizeMake(24, 32); }
CGImageRef SGLyricsClipBackdrop(CGImageRef cover, CGSize size) {
    return CGImageRetain(cover ?: blue.CGImage);
}
CGImageRef SGLyricsClipFrame(CGImageRef backdrop, NSString *line, NSString *translation, NSString *next, CGSize size) {
    return CGImageRetain(backdrop);
}
NSString *SGLyricsClipLook(NSURL *motion, SGLyricsClipStyle style) {
    return [NSString stringWithFormat:@"style%ld%@", (long)style, motion ? motion.lastPathComponent : @""];
}
static BOOL writeFrame(NSURL *file, CGImageRef frame) {
    NSData *data = UIImagePNGRepresentation([UIImage imageWithCGImage:frame]);
    return [data writeToURL:file atomically:YES];
}
BOOL SGLyricsClipWrite(NSURL *file, CGImageRef backdrop, NSString *line, NSString *translation, NSString *next,
                       CGSize size, SGLyricsClipStyle style) { return writeFrame(file, backdrop); }
BOOL SGLyricsClipWriteOverMotion(NSURL *file, NSURL *motion, NSString *previous, NSString *line, NSString *translation,
                                 NSString *next, double from, double seconds) { return writeFrame(file, blue.CGImage); }
CGImageRef SGLyricsClipMotionFrame(NSURL *motion, NSString *previous, NSString *line, NSString *translation,
                                   NSString *next, double from) { return CGImageRetain(blue.CGImage); }
BOOL SGMotionClipShape(NSURL *file, CGFloat ratio, NSURL *out) { return writeFrame(out, blue.CGImage); }
CGImageRef SGFluidClipFrame(CGImageRef cover, CGSize size) { return CGImageRetain(cover); }
BOOL SGFluidClipWrite(NSURL *file, CGImageRef cover, CGSize size) { return writeFrame(file, cover); }

// PlayerState.publish sends this callback on every accepted report, even when
// its URI/context/playback key is unchanged and it suppresses DidChange.
static void reportOnly(void) {
    for (id<SGPlayerStateObserver> observer in observers.allObjects) {
        if ([observer respondsToSelector:@selector(playerStateDidReport:)]) [observer playerStateDidReport:state];
    }
}
// Other lifecycle cases explicitly force a change (including simulated lyric seeks).
static void report(void) {
    reportOnly();
    for (id<SGPlayerStateObserver> observer in observers.allObjects) [observer playerStateDidChange:state];
}
static void choose(SGLockArtwork value) {
    choice = value;
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
    runFor(0.03);
}
static void track(NSString *uri, SGLockArtwork mode, NSURL *file, NSArray *lines) {
    choose(SGLockArtworkOff);
    sourceFile = file;
    state = harnessState(uri, @"Song");
    position = 0;
    harnessLines(lines);
    report();
    choose(mode);
}
static void nativeInfo(UIImage *cover) {
    NSMutableDictionary *info = [@{MPMediaItemPropertyTitle: @"Song", MPMediaItemPropertyArtist: @"Artist",
        MPNowPlayingInfoPropertyElapsedPlaybackTime: @0, MPNowPlayingInfoPropertyPlaybackRate: @0} mutableCopy];
    // MediaPlayer clamps handler requests to these bounds. Model a real album's full-resolution source;
    // the tiny solid returned image remains a renderer stand-in.
    if (cover) info[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithBoundsSize:CGSizeMake(2048, 2048)
        requestHandler:^UIImage *(CGSize size) { lastCoverRequest = size; return cover; }];
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = info;
}
static id artwork(void) { return harnessSystem()[MPNowPlayingInfoProperty3x4AnimatedArtwork]; }
static NSString *name(id art) { return objc_getAssociatedObject(art, &idKey); }
static void finishPoster(void) {
    check(posterCallbacks.count > 0, @"a controlled poster callback is pending");
    if (!posterCallbacks.count) return;
    void (^done)(UIImage *) = posterCallbacks.firstObject;
    [posterCallbacks removeObjectAtIndex:0];
    done(blue);
}
static BOOL await(BOOL (^done)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!done() && deadline.timeIntervalSinceNow > 0) runFor(0.01);
    return done();
}
static NSString *coverURL(NSString *key) {
    return [@"https://cover.invalid/" stringByAppendingString:key];
}
static void coverMetadata(NSString *key) {
    harnessMetadata(key ? @{@"image_xlarge_url": coverURL(key)} : @{});
    // Only metadata changed: production does not deliver DidChange, and there
    // need not be a native now-playing notification to wake the paused lyrics.
    reportOnly();
}
static void finishCover(NSString *key, UIImage *image) {
    NSString *url = coverURL(key);
    check(await(^BOOL { return coverRequests[url] != nil; }), @"metadata artwork reaches the real URL loader");
    NSURLProtocol *request = coverRequests[url];
    if (!request) return;
    [coverRequests removeObjectForKey:url];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:request.request.URL
        statusCode:image ? 200 : 404 HTTPVersion:@"HTTP/1.1" headerFields:nil];
    [request.client URLProtocol:request didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    if (image) [request.client URLProtocol:request didLoadData:UIImagePNGRepresentation(image)];
    [request.client URLProtocolDidFinishLoading:request];
    runFor(.05);
}
static UIImage *preview(id art) {
    Preview block = objc_getAssociatedObject(art, &previewKey);
    __block UIImage *result;
    __block BOOL done = NO;
    if (block) block(CGSizeMake(24, 32), ^(UIImage *value) {
        dispatch_async(dispatch_get_main_queue(), ^{ result = value; done = YES; });
    });
    check(await(^BOOL { return done; }), @"preview request completes");
    return result;
}
static NSURL *video(id art) {
    Video block = objc_getAssociatedObject(art, &videoKey);
    __block NSURL *result;
    __block BOOL done = NO;
    if (block) block(CGSizeMake(24, 32), ^(NSURL *value) {
        dispatch_async(dispatch_get_main_queue(), ^{ result = value; done = YES; });
    });
    check(await(^BOOL { return done; }), @"video request completes");
    return result;
}
// PNG encoders can attach different scale/color metadata to the same pixels. The stand-ins are solid
// colors, so compare their decoded center in one fixed RGB space, not their container bytes.
static uint32_t pixel(UIImage *image) {
    uint32_t value = 0;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(&value, 1, 1, 8, 4, space,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), image.CGImage);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    return value;
}
static BOOL sameImage(UIImage *a, UIImage *b) { return a.CGImage && b.CGImage && pixel(a) == pixel(b); }

static void background(NSDictionary *values) {
    NSMutableDictionary *domain = [NSMutableDictionary dictionary];
    for (NSString *key in values) domain[[@"spotifyglass.lockscreen.background." stringByAppendingString:key]] = values[key];
    [NSUserDefaults.standardUserDefaults setVolatileDomain:domain forName:NSArgumentDomain];
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
}

void artworkChecks(void) {
    red = image(UIColor.redColor);
    blue = image(UIColor.blueColor);
    UIImage *safe = image([UIColor colorWithRed:24 / 255. green:24 / 255. blue:27 / 255. alpha:1]);
    background(@{@"darkness": @0});
    runFor(.2);
    NSURL *file = [cacheRoot URLByAppendingPathComponent:@"source.mp4"];
    NSArray *lines = @[lineOf(@"First", 0, 10000), lineOf(@"Second", 12000, 20000)];
    supported = @[MPNowPlayingInfoProperty3x4AnimatedArtwork];
    nativeInfo(nil);
    runFor(0.03);

    // A whole burst on a posting thread must return without waiting for main, and emit just once.
    __block NSUInteger notifications = 0;
    id token = [NSNotificationCenter.defaultCenter addObserverForName:SGNowPlayingInfoDidChangeNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            check(NSThread.isMainThread, @"now-playing notification is delivered on main");
            notifications++;
        }];
    dispatch_semaphore_t posted = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        for (NSUInteger i = 0; i < 20; i++) nativeInfo(nil);
        dispatch_semaphore_signal(posted);
    });
    check(dispatch_semaphore_wait(posted, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0,
          @"background now-playing setters never wait for main");
    runFor(0.03);
    check(notifications == 1, @"native now-playing notification burst is coalesced");
    SGNowPlayingSetExtras(@"test", @{@"test": @YES}, @"Song");
    SGNowPlayingSetExtras(@"test", nil, nil);
    runFor(0.03);
    check(notifications == 1, @"extras resends do not generate notifications");
    [NSNotificationCenter.defaultCenter removeObserver:token];

    track(@"poster-race", SGLockArtworkMotionLyrics, file, @[]);
    SGLockMotionShowPlain(YES);
    harnessLines(lines);
    report();
    id lyric = artwork();
    check(lyric != nil, @"lyrics take ownership while the plain poster is pending");
    finishPoster();
    check(artwork() == lyric, @"late plain poster cannot replace lyric artwork");
    SGNowPlayingSetExtras(@"lyrics", nil, nil);
    check(!artwork(), @"late plain poster did not leave a hidden competing motion owner");

    track(@"poster-toggle", SGLockArtworkMotionLyrics, file, @[]);
    SGLockMotionShowPlain(YES);
    SGLockMotionShowPlain(NO);
    SGLockMotionShowPlain(YES);
    finishPoster();
    check(!artwork(), @"plain-to-lyrics-to-plain rejects the first poster generation");
    finishPoster();
    check(artwork() != nil, @"plain-to-lyrics-to-plain accepts the current poster");

    track(@"poster-old-track", SGLockArtworkMotion, file, @[]);
    choose(SGLockArtworkOff);
    finishPoster();
    check(!artwork(), @"a choice change invalidates an in-flight poster");
    track(@"poster-track-a", SGLockArtworkMotion, file, @[]);
    state = harnessState(@"poster-track-b", @"Song");
    report();
    finishPoster();
    check(!artwork(), @"a same-title track change invalidates the old poster");
    finishPoster();
    check(artwork() != nil, @"the new track's poster still publishes");

    supported = @[];
    track(@"late-capability", SGLockArtworkMotion, file, @[]);
    NSUInteger fetched = lookups, decoded = posters, sets = harnessSets();
    for (NSUInteger i = 0; i < 5; i++) { nativeInfo(nil); runFor(0.01); }
    check(lookups == fetched && posters == decoded && !artwork(),
          @"unsupported capability does not refetch, decode or publish on repeated updates");
    runFor(0.1);
    check(harnessSets() == sets + 5, @"unsupported capability creates no polling/resend loop");
    supported = @[MPNowPlayingInfoProperty3x4AnimatedArtwork];
    nativeInfo(nil);
    runFor(0.03);
    finishPoster();
    check(artwork() && lookups == fetched, @"late capability publishes the same track without downloading again");
    sets = harnessSets();
    runFor(0.1);
    check(harnessSets() == sets, @"recovered publication does not recursively resend");

    supported = @[];
    track(@"cancel-pending", SGLockArtworkMotion, file, @[]);
    decoded = posters;
    choose(SGLockArtworkOff);
    supported = @[MPNowPlayingInfoProperty3x4AnimatedArtwork];
    nativeInfo(nil);
    runFor(0.03);
    check(!artwork() && posters == decoded, @"disabled artwork cannot revive a capability-waiting offer");

    supported = @[];
    track(@"plain-capability", SGLockArtworkMotionLyrics, file, @[]);
    SGLockMotionShowPlain(YES);
    decoded = posters;
    harnessLines(lines);
    report();
    lyric = artwork();
    supported = @[MPNowPlayingInfoProperty3x4AnimatedArtwork];
    nativeInfo(nil);
    runFor(0.03);
    check(artwork() == lyric && posters == decoded, @"lyrics ownership cancels a capability-waiting plain offer");

    supported = @[];
    track(@"plain-late-capability", SGLockArtworkMotionLyrics, file, @[]);
    SGLockMotionShowPlain(YES);
    fetched = lookups;
    supported = @[MPNowPlayingInfoProperty3x4AnimatedArtwork];
    nativeInfo(nil);
    runFor(0.03);
    finishPoster();
    check(artwork() && lookups == fetched, @"plain motion recovers late capability without a new lookup");

    nativeInfo(nil);
    runFor(.03);
    NSUInteger prepared = preparations();
    dispatch_semaphore_t entered = dispatch_semaphore_create(0), release = dispatch_semaphore_create(0);
    @synchronized (cacheRoot) {
        heldPicture = @"cover-during-render";
        renderEntered = entered;
        renderRelease = release;
        renderGateTimedOut = NO;
    }
    track(@"cover-during-render", SGLockArtworkEverySong, nil, @[]);
    check(dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0,
          @"coverless background worker is held before rendering");
    fetched = lookups;
    __block BOOL coverInfoDelivered = NO;
    id coverInfoToken = [NSNotificationCenter.defaultCenter addObserverForName:SGNowPlayingInfoDidChangeNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) { coverInfoDelivered = YES; }];
    nativeInfo(red);
    check(await(^BOOL { return coverInfoDelivered; }), @"late-cover info is delivered while the worker is held");
    [NSNotificationCenter.defaultCenter removeObserver:coverInfoToken];
    sets = harnessSets();
    dispatch_semaphore_signal(release);
    // No native update follows release: the coverless completion itself must recover the missed info.
    check(await(^BOOL { return harnessSets() >= sets + 2; }),
          @"cover arriving during rendering recovers the paused track without another native event");
    check(sameImage(preview(artwork()), red), @"recovered in-flight cover is the real album image");
    runFor(.1);
    check(preparations() == prepared + 2 && harnessSets() == sets + 2 && lookups == fetched,
          @"in-flight recovery makes only two bounded offers and no source re-download");
    @synchronized (cacheRoot) { check(!renderGateTimedOut, @"held render was explicitly released, not timed out"); }

    nativeInfo(nil);
    runFor(.03);
    prepared = preparations();
    track(@"cover-never-arrives", SGLockArtworkEverySong, nil, @[]);
    check(await(^BOOL { return artwork() != nil; }), @"permanently coverless track publishes its safe fallback");
    fetched = lookups;
    sets = harnessSets();
    for (NSUInteger i = 0; i < 5; i++) nativeInfo(nil);
    runFor(.1);
    check(preparations() == prepared + 1 && harnessSets() == sets + 5 && lookups == fetched,
          @"a cover that never arrives stays bounded across completion and later native updates");

    supported = @[];
    nativeInfo(nil);
    track(@"fluid-late", SGLockArtworkEverySong, nil, @[]);
    fetched = lookups;
    supported = @[MPNowPlayingInfoProperty3x4AnimatedArtwork];
    nativeInfo(nil);
    runFor(0.03);
    id safeFallback = artwork();
    check(safeFallback != nil, @"Every song offers a safe selected fallback before the cover arrives");
    nativeInfo(red);
    runFor(0.03);
    id fluid = artwork();
    check(fluid && lookups == fetched, @"paused late cover recovers Every song without a new lookup");
    check(![name(fluid) isEqual:name(safeFallback)], @"late cover does not reuse the no-cover fallback's disk identity");
    // The clip-size stand-in above deliberately returns 24x32, independently of the screen.
    check(lastCoverRequest.width == 32 && lastCoverRequest.height == 32, @"cover acquisition requests the intended full raster");
    nativeInfo(blue);
    runFor(0.03);
    check(sameImage(preview(fluid), red), @"lazy fluid preview retains the offered cover");
    NSURL *fluidFile = video(fluid);
    check(sameImage(red, [UIImage imageWithContentsOfFile:fluidFile.path]),
          @"lazy fluid video uses the offered cover");

    fetched = lookups;
    background(@{@"mode": @4, @"darkness": @0, @"color": @0x0000FF});
    runFor(.2);
    id solid = artwork();
    check(solid && ![name(solid) isEqual:name(fluid)] && lookups == fetched,
          @"paused Every song background changes identity without a source lookup");
    check(sameImage(preview(solid), blue), @"Every song uses the selected solid color");
    check(preview(fluid) == nil, @"old fallback request cannot return a stale preview after settings change");
    background(@{@"darkness": @0});
    runFor(.2);

    nativeInfo(nil);
    track(@"lyrics-late-cover", SGLockArtworkLyrics, nil, lines);
    id empty = artwork();
    check(sameImage(preview(empty), safe), @"coverless lyric preview uses the shared safe backdrop");
    NSURL *emptyFile = video(empty);
    check(emptyFile != nil, @"coverless lyric video is cached on disk");
    // A fresh report draws the next line ahead while requests are recent.
    position = 12000;
    report();
    position = 0;
    report();
    nativeInfo(red);
    coverMetadata(@"lyrics-late-cover");
    finishCover(@"lyrics-late-cover", red);
    runFor(0.03);
    id covered = artwork();
    check(covered && ![name(covered) isEqual:name(empty)], @"paused late cover changes the current render identity");
    check(sameImage(preview(covered), red), @"late cover replaces the cached current preview");
    NSURL *coveredFile = video(covered);
    check(coveredFile && ![coveredFile isEqual:emptyFile]
          && [NSFileManager.defaultManager fileExistsAtPath:emptyFile.path],
          @"late cover uses a distinct disk file while the coverless file still exists");
    check(sameImage(red, [UIImage imageWithContentsOfFile:coveredFile.path]),
          @"the new disk file contains the real cover");
    position = 12000;
    report();
    id next = artwork();
    check(sameImage(preview(next), red), @"prefetched next preview uses the real-cover identity");
    NSURL *nextFile = video(next);
    check(sameImage(red, [UIImage imageWithContentsOfFile:nextFile.path]),
          @"prefetched next disk clip uses the real-cover identity");
    sets = harnessSets();
    nativeInfo(red);
    runFor(0.03);
    check(harnessSets() == sets + 1, @"unchanged cover/line does not republish or loop");
    position = 0;
    report();
    id previousStyle = artwork();
    sets = harnessSets();
    fetched = lookups;
    for (NSUInteger i = 0; i < 20; i++) background(@{@"mode": @4, @"darkness": @0, @"color": @(0x0000FF + i)});
    runFor(.25);
    id changedStyle = artwork();
    check(changedStyle && ![name(changedStyle) isEqual:name(previousStyle)] && lookups == fetched,
          @"paused lyric background changes current render identity without downloading");
    check(harnessSets() <= sets + 2, @"slider burst coalesces to one clear and one publication");
    check(preview(previousStyle) == nil && video(previousStyle) == nil, @"stale lyric requests are cancelled after a style change");
    NSURL *styleFile = video(changedStyle);
    check(styleFile && ![styleFile isEqual:coveredFile], @"style change creates a distinct current disk clip");
    position = 12000;
    report();
    NSURL *styleNext = video(artwork());
    check(styleNext && ![styleNext isEqual:nextFile], @"style change creates a distinct prefetched disk clip");
    choose(SGLockArtworkOff);
    nativeInfo(nil);
    runFor(0.03);
    check(!artwork(), @"late now-playing info cannot revive disabled lyrics");

    background(@{@"darkness": @0});
    runFor(.2);
    // A non-nil native placeholder is not a missing image. The old test supplied nil,
    // so it never exposed the first-image-wins latch or the title-only identity.
    UIImage *placeholder = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(24, 32)]
        imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [UIColor.blackColor setFill];
            UIRectFill(CGRectMake(0, 0, 24, 32));
            [[[UIImage systemImageNamed:@"photo"] imageWithTintColor:UIColor.grayColor
                renderingMode:UIImageRenderingModeAlwaysOriginal] drawInRect:CGRectMake(0, 4, 24, 24)];
        }];
    nativeInfo(placeholder);
    track(@"source-placeholder", SGLockArtworkLyrics, nil, lines);
    check(state.isPaused, @"metadata-only artwork regression runs with the lyric timer stopped");
    coverMetadata(@"source-real");
    check(await(^BOOL { return coverRequests[coverURL(@"source-real")] != nil; }),
          @"paused report-only late metadata starts a cover load without a native info update");
    runFor(.05);
    id pending = artwork();
    check(sameImage(preview(pending), safe), @"native placeholder never enters the lyric preview while metadata cover loads");
    NSURL *pendingFile = video(pending);
    check(sameImage([UIImage imageWithContentsOfFile:pendingFile.path], safe),
          @"native placeholder never enters the lyric disk clip");
    finishCover(@"source-real", red);
    id resolved = artwork();
    check(![name(resolved) isEqual:name(pending)] && sameImage(preview(resolved), red),
          @"metadata real cover replaces fallback even while native artwork remains a placeholder");
    check(sameImage([UIImage imageWithContentsOfFile:video(resolved).path], red),
          @"metadata real cover reaches the disk clip");
    position = 12000;
    report();
    check(sameImage(preview(artwork()), red), @"metadata real cover reaches the prefetched next line");

    nativeInfo(red); // Previous track's real cover, same title as the next track.
    track(@"source-old", SGLockArtworkLyrics, nil, lines);
    coverMetadata(@"source-old");
    check(await(^BOOL { return coverRequests[coverURL(@"source-old")] != nil; }), @"old track cover request is held");
    state = harnessState(@"source-new", @"Song");
    report();
    coverMetadata(@"source-new");
    check(sameImage(preview(artwork()), safe), @"same-title track never inherits native artwork from the previous URI");
    finishCover(@"source-new", blue);
    finishCover(@"source-old", red);
    check(sameImage(preview(artwork()), blue), @"late old-URI completion cannot replace the current cover");

    coverMetadata(@"source-revised-old");
    check(await(^BOOL { return coverRequests[coverURL(@"source-revised-old")] != nil; }),
          @"paused report-only revised metadata starts a cover load without a native info update");
    coverMetadata(@"source-revised-new");
    finishCover(@"source-revised-new", red);
    finishCover(@"source-revised-old", blue);
    check(sameImage(preview(artwork()), red), @"late old-URL completion cannot replace revised metadata for the same URI");
    coverMetadata(@"source-unavailable");
    finishCover(@"source-unavailable", nil);
    check(sameImage(preview(artwork()), safe), @"failed authoritative artwork uses dark fallback, not native placeholder or stale cover");
    NSUInteger loads = coverLoads;
    for (NSUInteger i = 0; i < 5; i++) { report(); nativeInfo(placeholder); }
    runFor(.1);
    check(coverLoads == loads, @"failed artwork does not trigger a download loop");
    coverMetadata(@"source-disabled");
    check(await(^BOOL { return coverRequests[coverURL(@"source-disabled")] != nil; }), @"cover request starts before disabling");
    choose(SGLockArtworkOff);
    finishCover(@"source-disabled", red);
    check(!artwork(), @"late metadata cover cannot revive disabled lyrics");
}
