// Compile the real engine, replacing only its system PiP transport. No real PiP/audio session starts.
#import "tests.h"
#import <objc/runtime.h>
#import "../../tweak/Sources/Shared/LyricsPiP/LyricsPiP.m"

@implementation SPTPlayerTrack
- (id)URI { return SGTestTrackURI(); }
@end
@implementation SPTPlayerState
- (SPTPlayerTrack *)track { return [SPTPlayerTrack new]; }
- (BOOL)isPlaying { return NO; }
- (BOOL)isPaused { return YES; }
- (BOOL)isLoading { return NO; }
- (double)duration { return 180; }
- (double)playbackSpeed { return 1; }
@end
@interface TestPlayer : NSObject
@property (nonatomic) NSUInteger pauses, resumes;
@end
@implementation TestPlayer
- (SPTPlayerState *)state { return [SPTPlayerState new]; }
- (id)pause:(id)options { _pauses++; return nil; }
- (id)resume:(id)options { _resumes++; return nil; }
@end
static TestPlayer *player;
static NSInteger position = 1500;
static NSString *credit = @"Spicy Lyrics · Maker · Uploader https://example.org/credit";
NSString *SGURIString(id uri) { return [uri isKindOfClass:NSURL.class] ? [uri absoluteString] : uri; }
SPTPlayerState *SGPlayerState(void) { return [SPTPlayerState new]; }
void SGAddPlayerStateObserver(id observer) {}
NSString *SGKaraokePlayingTrack(void) {
    return [SGTestTrackURI() hasPrefix:@"spotify:track:"] ? [SGTestTrackURI() substringFromIndex:14] : SGTestTrackURI();
}
id SGKaraokePlayer(void) { return player; }
NSInteger SGKaraokePositionMs(void) { return position; }
NSInteger SGKaraokeDelayMs(void) { return 0; }
void SGKaraokeSeek(NSInteger ms) { position = ms; }
NSArray *SGKaraokeLinesForTrack(NSString *track) { return @[]; }
void SGKaraokeRequestLyrics(NSString *track) {}
NSString *SGLyricsCreditFor(NSString *track) { return credit; }
NSArray *SGLyricsCreditLinks(NSString *text) { return @[]; }
void SGLyricsOpenCreditLinks(NSArray *links, UIView *from) {}
NSNotificationName const SGKaraokeLinesKeptNotification = @"test.lines";
NSNotificationName const SGLyricsOffsetsDidChangeNotification = @"test.offset";
NSNotificationName const SGLyricsDidReloadNotification = @"test.reload";
NSNotificationName const SGNowPlayingInfoDidChangeNotification = @"test.artwork";
NSString *SGL(NSString *key, NSString *english) { return english; }
BOOL SGFlag(NSString *key, BOOL fallback) { return fallback; }
void SGPresentDark(UIViewController *controller) {}

static NSUInteger alerts;
@interface TestPresenter : UIViewController
@end
@implementation TestPresenter
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    if ([controller isKindOfClass:UIAlertController.class]) {
        UIAlertController *alert = (id)controller;
        SGTestAssert([alert.message isEqual:@"Enable Picture in Picture lyrics in Vitrine settings → Lyrics, then restart Spotify."],
            @"disabled tap gives exact activation and restart guidance");
        alerts++;
    }
    if (completion) completion();
}
@end
static TestPresenter *presenter;
UIViewController *SGTopController(void) { return presenter; }
// The engine needs only window identity and a presenter; creating a real UIWindow would require
// NSApplication/UIApplicationMain and turn this host-only lifecycle check into an application run.
@interface TestWindow : NSObject
@end
@implementation TestWindow
- (UIViewController *)rootViewController { return presenter; }
@end
static TestWindow *window;
@interface TestSource : UIView
@end
@implementation TestSource
- (UIWindow *)window { return (id)window; }
@end
UIView *SGTestSourceView(void) { return [TestSource new]; }
NSUInteger SGTestDisabledAlerts(void) { return alerts; }

@interface TestPiP : NSObject
@property (nonatomic, getter=isPictureInPicturePossible) BOOL pictureInPicturePossible;
@property (nonatomic, strong) id contentSource;
@property (nonatomic) NSUInteger starts, stops, invalidations;
@end
@implementation TestPiP
- (void)startPictureInPicture { _starts++; }
- (void)stopPictureInPicture { _stops++; }
- (void)invalidatePlaybackState { _invalidations++; }
@end

@interface TestLayer : AVSampleBufferDisplayLayer
@property (nonatomic) NSUInteger frames, flushes;
@end
@implementation TestLayer
- (BOOL)isReadyForMoreMediaData { return YES; }
- (AVQueuedSampleBufferRenderingStatus)status { return AVQueuedSampleBufferRenderingStatusRendering; }
- (void)enqueueSampleBuffer:(CMSampleBufferRef)sample {
    SGTestAssert(CMSampleBufferGetImageBuffer(sample) != NULL, @"real engine enqueues a rendered pixel buffer");
    _frames++;
}
- (void)flushAndRemoveImage { _flushes++; }
@end

@interface TestEngine : SGLyricsPiPEngine
@property (nonatomic, strong) TestLayer *testLayer;
@end
@implementation TestEngine
- (AVSampleBufferDisplayLayer *)displayLayer { return self.testLayer; }
- (BOOL)prepareIn:(UIWindow *)source {
    self.testLayer = [TestLayer new];
    if (!_timebase) CMTimebaseCreateWithSourceClock(kCFAllocatorDefault, CMClockGetHostTimeClock(), &_timebase);
    if (!_pool) {
        NSDictionary *attributes = @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (__bridge NSString *)kCVPixelBufferWidthKey: @640, (__bridge NSString *)kCVPixelBufferHeightKey: @360,
            (__bridge NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
            (__bridge NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES};
        CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (__bridge CFDictionaryRef)attributes, &_pool);
    }
    TestPiP *pip = [TestPiP new];
    pip.pictureInPicturePossible = YES;
    [pip addObserver:self forKeyPath:@"pictureInPicturePossible" options:0 context:kPossibleContext];
    self.pip = (id)pip;
    return _pool && _timebase;
}
@end

void SGTestPiPState(BOOL enabled, BOOL active, BOOL starting) {
    [sg_engine finish];
    sg_engine = [TestEngine new];
    [sg_engine prepareIn:(id)window];
    sg_enabled = enabled;
    sg_engine.active = active;
    sg_engine.starting = starting;
}

void SGTestLifecycle(void) {
    player = [TestPlayer new];
    presenter = [TestPresenter new];
    window = [TestWindow new];
    // Report supported without constructing or starting a real system PiP controller.
    Method supported = class_getClassMethod(AVPictureInPictureController.class, @selector(isPictureInPictureSupported));
    method_setImplementation(supported, imp_implementationWithBlock(^BOOL(id object) { return YES; }));
    SGTestSetTrack(@"spotify:track:A", nil);
    SGTestPiPState(NO, NO, NO);
    SGLyricsPiPToggle(SGTestSourceView());
    SGTestAssert(alerts == 1 && !SGLyricsPiPStarting(), @"disabled action never force-enables or starts");
    SGTestPiPState(YES, NO, NO);
    TestEngine *engine = (id)sg_engine;
    [engine refresh];
    SGTestAssert(engine.testLayer.frames == 0 && engine.background.image == nil, @"inactive refresh creates no frame or artwork");
    SGLyricsPiPToggle(SGTestSourceView());
    SGTestAssert(SGTestPump(^BOOL { return engine.shown != nil; }), @"user open prepares first production frame");
    TestPiP *pip = (id)engine.pip;
    SGTestAssert(pip.starts == 1 && engine.starting && !engine.active, @"readiness starts only once after first frame");
    SGTestAssert([SGLyricsPiPMenuTitle() isEqual:@"Close lyrics Picture in Picture"], @"starting action is cancel/close");
    SGTestAssert([engine.shown.lastObject isEqual:credit], @"provider maker/uploader credit is never filtered");
    NSUInteger frames = engine.testLayer.frames;
    for (int i = 0; i < 20; i++) [engine refresh];
    SGTestAssert(engine.testLayer.frames == frames, @"unchanged content and background do not repeat frames");
    [engine pictureInPictureControllerDidStartPictureInPicture:(id)pip];
    SGTestAssert(engine.active && !engine.starting && engine.timer == nil, @"paused active session has no render timer");
    SGTestSetting(@"spotifyglass.lyrics.pip.background.darkness", @60);
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
    SGTestAssert(SGTestPump(^BOOL { return engine.testLayer.frames > frames; }), @"paused defaults notification refreshes actual engine");
    frames = engine.testLayer.frames;
    SGTestSetTrack(@"spotify:track:A", @"https://i.scdn.co/image/late");
    [NSNotificationCenter.defaultCenter postNotificationName:SGNowPlayingInfoDidChangeNotification object:nil];
    SGTestAssert(SGTestPump(^BOOL { return SGTestArtworkRequests() > 0; }), @"late artwork notification refreshes paused source");
    SGTestTakeArtwork()(SGTestCover());
    SGTestAssert(SGTestPump(^BOOL { return engine.testLayer.frames > frames; }), @"late cover refreshes actual paused frame");
    SGLyricsPiPToggle(SGTestSourceView());
    SGTestAssert(pip.stops == 1 && player.pauses == 0, @"close stops PiP without pausing Spotify");
    [engine pictureInPictureControllerDidStopPictureInPicture:(id)pip];
    SGTestAssert(!engine.active && engine.background.image == nil, @"stop clears pending background ownership");
    SGTestSetTrack(@"spotify:track:B", nil);
    SGLyricsPiPToggle(SGTestSourceView());
    TestPiP *cancelled = (id)engine.pip;
    SGLyricsPiPToggle(SGTestSourceView());
    SGTestAssert(!engine.starting && !engine.active && cancelled.stops == 1, @"second tap cancels pending start");
    SGLyricsPiPToggle(SGTestSourceView());
    TestPiP *newAttempt = (id)engine.pip;
    [engine pictureInPictureControllerDidStartPictureInPicture:(id)cancelled];
    [engine pictureInPictureControllerDidStopPictureInPicture:(id)cancelled];
    SGTestAssert(engine.pip == (id)newAttempt && engine.starting && !engine.active, @"stale delegate cannot start or tear down next attempt");
    [engine finish];
    SGTestPiPState(NO, NO, NO);
    SGTestSetTrack(@"spotify:track:menus", nil);
}
