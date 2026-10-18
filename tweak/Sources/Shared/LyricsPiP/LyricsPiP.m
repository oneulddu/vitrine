// One CPU-rendered still frame per content change, on Spotify's own playback clock.
// Never owns an audio session or player. Everything, including rendering, is serialized on main.
#import "LyricsPiP.h"
#import "LyricsPiPText.h"
#import "Core/SGCore.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/Player/PlayerState.h"
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreText/CoreText.h>
#import <math.h>

NSNotificationName const SGLyricsPiPDidChangeNotification = @"spotifyglass.lyrics.pip.didChange";
static BOOL sg_enabled;
static const size_t kWidth = 640, kHeight = 360;
static void *kPossibleContext = &kPossibleContext;

@interface SGLyricsPiPHost : UIView
@end
@implementation SGLyricsPiPHost
+ (Class)layerClass { return AVSampleBufferDisplayLayer.class; }
@end

@interface SGLyricsPiPEngine : NSObject <AVPictureInPictureControllerDelegate,
    AVPictureInPictureSampleBufferPlaybackDelegate, SGPlayerStateObserver> {
    CVPixelBufferPoolRef _pool;
    CMTimebaseRef _timebase;
}
@property (nonatomic, strong) SGLyricsPiPHost *host;
@property (nonatomic, strong) AVPictureInPictureController *pip;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, weak) UIWindow *window;
@property (nonatomic, copy) NSString *track;
@property (nonatomic, copy) NSArray<NSString *> *shown;
@property (nonatomic) BOOL active, starting, startRequested, stopping, playing, alertPending, restoreCredit, retryPending;
@property (nonatomic) NSUInteger generation, attempt;
@property (nonatomic) double duration, position, speed;
- (void)toggleFrom:(UIView *)from;
- (void)refresh;
@end

static SGLyricsPiPEngine *sg_engine;

BOOL SGLyricsPiPEnabled(void) { return sg_enabled; }
BOOL SGLyricsPiPActive(void) { return sg_engine.active; }
BOOL SGLyricsPiPStarting(void) { return sg_engine.starting; }
void SGLyricsPiPToggle(UIView *from) {
    if (!sg_enabled) return;
    if (!sg_engine) sg_engine = [SGLyricsPiPEngine new];
    [sg_engine toggleFrom:from];
}

// Core Text draws into a bottom-left-origin bitmap. Credits are fitted in full, including the
// maker/uploader text Spicy Lyrics supplies; they are never governed by the Show source switch.
static void drawText(CGContextRef context, NSString *text, CGRect rect, CGFloat size, CGFloat white) {
    if (!text.length) return;
    CTTextAlignment alignment = kCTTextAlignmentCenter;
    CTParagraphStyleSetting setting = {kCTParagraphStyleSpecifierAlignment, sizeof(alignment), &alignment};
    CTParagraphStyleRef paragraph = CTParagraphStyleCreate(&setting, 1);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceGray();
    CGFloat components[] = {white, 1};
    CGColorRef color = CGColorCreate(space, components);
    CGColorSpaceRelease(space);
    CTFramesetterRef setter = NULL;
    for (;;) {
        CTFontRef font = CTFontCreateWithName(CFSTR("HelveticaNeue"), size, NULL);
        NSDictionary *attributes = @{(__bridge NSString *)kCTFontAttributeName: (__bridge id)font,
            (__bridge NSString *)kCTForegroundColorAttributeName: (__bridge id)color,
            (__bridge NSString *)kCTParagraphStyleAttributeName: (__bridge id)paragraph};
        NSAttributedString *string = [[NSAttributedString alloc] initWithString:text attributes:attributes];
        setter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)string);
        CFRelease(font);
        CGSize needed = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRangeMake(0, 0), NULL,
                                                                     CGSizeMake(rect.size.width, CGFLOAT_MAX), NULL);
        if (needed.height <= rect.size.height || size <= 2) break;
        CFRelease(setter);
        size = MAX(2, size - 1);
    }
    CGPathRef path = CGPathCreateWithRect(rect, NULL);
    CTFrameRef frame = CTFramesetterCreateFrame(setter, CFRangeMake(0, 0), path, NULL);
    CGContextSetTextMatrix(context, CGAffineTransformIdentity);
    CTFrameDraw(frame, context);
    CFRelease(frame);
    CGPathRelease(path);
    CFRelease(setter);
    CGColorRelease(color);
    CFRelease(paragraph);
}

@implementation SGLyricsPiPEngine

- (instancetype)init {
    if (!(self = [super init])) return nil;
    SGAddPlayerStateObserver(self);
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    // No queued notification observer: a posting Spotify thread must never wait for main.
    [center addObserver:self selector:@selector(lyricsChanged:) name:SGKaraokeLinesKeptNotification object:nil];
    [center addObserver:self selector:@selector(lyricsChanged:) name:SGLyricsOffsetsDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(lyricsChanged:) name:SGLyricsDidReloadNotification object:nil];
    [center addObserver:self selector:@selector(foreground:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(background:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    return self;
}

- (AVSampleBufferDisplayLayer *)displayLayer { return (AVSampleBufferDisplayLayer *)self.host.layer; }

- (void)announce {
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsPiPDidChangeNotification object:nil];
}

- (void)showFailure {
    if (!_alertPending || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    UIViewController *presenter = _window.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    if (!presenter || presenter.isBeingDismissed) return;
    _alertPending = NO;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.lyrics.pip.title", @"Picture in Picture lyrics")
        message:SGL(@"settings.lyrics.pip.failed", @"Picture in Picture could not start. This device or Spotify's current playback session may not support it. Keep Spotify in front and try again.")
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.ok", @"OK") style:UIAlertActionStyleDefault handler:nil]];
    SGPresentDark(alert);
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)fail:(NSString *)reason {
    SGLog(@"lyrics PiP: %@", reason);
    _stopping = YES;
    [_pip stopPictureInPicture];
    [self finish];
    _alertPending = YES;
    [self showFailure];
}

- (void)finish {
    _attempt++;
    _generation++;
    _retryPending = NO;
    _starting = NO;
    _startRequested = NO;
    _stopping = NO;
    _active = NO;
    [_timer invalidate];
    _timer = nil;
    [self.displayLayer flushAndRemoveImage];
    if (_timebase) CMTimebaseSetRate(_timebase, 0);
    [_host removeFromSuperview];
    _shown = nil;
    _track = nil;
    // A cancelled start may still deliver callbacks. Give the next attempt its own controller
    // identity so an old didStart/didStop can never start or tear down the new session.
    [_pip removeObserver:self forKeyPath:@"pictureInPicturePossible" context:kPossibleContext];
    _pip.contentSource = nil;
    _pip = nil;
    if (_pool) { CVPixelBufferPoolRelease(_pool); _pool = NULL; }
    [self announce];
}

- (BOOL)prepareIn:(UIWindow *)window {
    if (!_host) {
        _host = [[SGLyricsPiPHost alloc] initWithFrame:CGRectZero];
        _host.userInteractionEnabled = NO;
        _host.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        _host.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [_host.widthAnchor constraintEqualToConstant:160], [_host.heightAnchor constraintEqualToConstant:90]
        ]];
        self.displayLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        OSStatus status = CMTimebaseCreateWithSourceClock(kCFAllocatorDefault, CMClockGetHostTimeClock(), &_timebase);
        if (status != noErr) return NO;
        self.displayLayer.controlTimebase = _timebase;
    }
    if (!_timebase) return NO;
    if (!_pip) {
        AVPictureInPictureControllerContentSource *source = [[AVPictureInPictureControllerContentSource alloc]
            initWithSampleBufferDisplayLayer:self.displayLayer playbackDelegate:self];
        _pip = [[AVPictureInPictureController alloc] initWithContentSource:source];
        _pip.delegate = self;
        _pip.canStartPictureInPictureAutomaticallyFromInline = NO;
        [_pip addObserver:self forKeyPath:@"pictureInPicturePossible" options:NSKeyValueObservingOptionNew context:kPossibleContext];
    }
    if (!_pip) return NO;
    if (!_pool) {
        NSDictionary *attributes = @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (__bridge NSString *)kCVPixelBufferWidthKey: @(kWidth), (__bridge NSString *)kCVPixelBufferHeightKey: @(kHeight),
            (__bridge NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
            (__bridge NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
            (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}};
        if (CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (__bridge CFDictionaryRef)attributes, &_pool) != kCVReturnSuccess) return NO;
    }
    _host.alpha = 1;
    [window addSubview:_host];
    [NSLayoutConstraint activateConstraints:@[
        [_host.leadingAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.leadingAnchor constant:12],
        [_host.bottomAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.bottomAnchor constant:-64]
    ]];
    [window layoutIfNeeded];
    return YES;
}

- (void)toggleFrom:(UIView *)from {
    if (_active) { _stopping = YES; [_pip stopPictureInPicture]; return; }
    if (_starting) { _stopping = YES; [_pip stopPictureInPicture]; [self finish]; return; }
    _window = from.window;
    if (![AVPictureInPictureController isPictureInPictureSupported] || !_window ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
        [self fail:@"unsupported device or no foreground source window"];
        return;
    }
    if (![self prepareIn:_window]) { [self fail:@"could not prepare the display layer or pixel buffer pool"]; return; }
    _starting = YES;
    _startRequested = NO;
    _alertPending = NO;
    _restoreCredit = NO;
    NSUInteger attempt = ++_attempt;
    [self announce];
    [self refresh]; // enqueue a real first image before asking whether PiP is possible
    [self startIfPossible];
    __weak SGLyricsPiPEngine *weakSelf = self;
    // A bounded readiness/start deadline, not a repeating render timer.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        SGLyricsPiPEngine *engine = weakSelf;
        if (engine.starting && engine.attempt == attempt) [engine fail:@"timed out waiting for PiP under Spotify's audio session"];
    });
}

- (void)startIfPossible {
    if (!_starting || _startRequested || !_shown || !_pip.isPictureInPicturePossible ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    _startRequested = YES;
    [_pip startPictureInPicture];
}

- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != kPossibleContext) { [super observeValueForKeyPath:path ofObject:object change:change context:context]; return; }
    dispatch_async(dispatch_get_main_queue(), ^{ [self startIfPossible]; });
}

- (void)lyricsChanged:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!note.object || [note.object isEqual:self.track]) [self refresh];
    });
}

- (void)foreground:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showFailure];
        [self showRestoredCredit];
    });
}

- (void)background:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.starting && !self.startRequested) [self fail:@"left the foreground before PiP was ready"];
    });
}

- (void)playerStateDidChange:(SPTPlayerState *)state { [self scheduleRefresh]; }
- (void)playerStateDidReport:(SPTPlayerState *)state { [self scheduleRefresh]; }

- (void)scheduleRefresh {
    if (!_active && !_starting) return;
    NSUInteger generation = _generation;
    // Karaoke's observer may run after ours; read its track/clock after all observers have seen the report.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation == self.generation) [self refresh];
    });
}

- (void)resetFrames {
    _generation++;
    _shown = nil;
    [self.displayLayer flushAndRemoveImage];
}

- (void)refresh {
    if (!_active && !_starting) return;
    if (self.displayLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
        [self fail:[NSString stringWithFormat:@"display layer failed: %@", self.displayLayer.error]];
        return;
    }
    NSString *track = SGKaraokePlayingTrack();
    SPTPlayerState *state = [(id<SPTPlayer>)SGKaraokePlayer() state];
    double position = MAX(0, SGKaraokePositionMs()) / 1000.0;
    BOOL changedTrack = ![_track isEqualToString:track] && (_track || track);
    double clock = CMTimeGetSeconds(CMTimebaseGetTime(_timebase));
    // Position-only reports include scrubs. A discontinuity retires the previous track/seek's image.
    BOOL jumped = !isfinite(clock) || fabs(clock - position) > 0.25;
    if (changedTrack || jumped) [self resetFrames];
    BOOL playing = state && state.isPlaying && !state.isPaused && !state.isLoading;
    double duration = isfinite(state.duration) && state.duration > 0 ? state.duration : 0;
    double speed = isfinite(state.playbackSpeed) && state.playbackSpeed > 0 ? state.playbackSpeed : 1;
    BOOL playbackChanged = changedTrack || jumped || playing != _playing || duration != _duration || speed != _speed;
    _track = [track copy];
    _position = position;
    _duration = duration;
    _playing = playing;
    _speed = speed;
    CMTimebaseSetTime(_timebase, CMTimeMakeWithSeconds(position, 1000));
    CMTimebaseSetRate(_timebase, _playing ? _speed : 0);
    if (playbackChanged || !_duration) [_pip invalidatePlaybackState];
    if (_active && _playing && !_timer) {
        __weak SGLyricsPiPEngine *weakSelf = self;
        _timer = [NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) { [weakSelf refresh]; }];
        [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    } else if (!_active || !_playing) {
        [_timer invalidate];
        _timer = nil;
    }
    if (track.length && !SGKaraokeLinesForTrack(track)) SGKaraokeRequestLyrics(track);
    NSArray<SGKaraokeLine *> *lines = track.length ? SGKaraokeLinesForTrack(track) : nil;
    NSString *current = nil, *next = nil;
    SGLyricsPiPTextKind kind = SGLyricsPiPTextFor(lines, SGKaraokePositionMs() - SGKaraokeDelayMs(), &current, &next);
    if (kind == SGLyricsPiPTextNoLyrics) {
        current = SGL(@"settings.lyrics.pip.no_lyrics", @"No lyrics available");
    } else if (kind == SGLyricsPiPTextInstrumental) {
        current = SGL(@"settings.lyrics.pip.instrumental", @"Instrumental");
    } else if (kind == SGLyricsPiPTextUntimed) {
        next = SGL(@"settings.lyrics.pip.untimed", @"These lyrics are not synced");
    }
    NSString *credit = track.length ? SGLyricsCreditFor(track) : nil;
    // Always credit every provider, a stronger rule than SGLyricsCreditRequired: full Spicy
    // maker/uploader attribution even with Show source off. Linked again on return from PiP.
    NSArray<NSString *> *content = @[current ?: @"", next ?: @"", credit ?: @""];
    if (![_shown isEqualToArray:content]) [self enqueue:content generation:_generation];
    [self startIfPossible];
}

// A layer that is not ready, or a full pool, would otherwise drop the frame with nothing left to
// show it: a start waits on _shown, and a paused engine has no repeating refresh.
- (void)scheduleRetry {
    if (_retryPending || (!_active && !_starting)) return;
    _retryPending = YES;
    NSUInteger attempt = _attempt;
    __weak SGLyricsPiPEngine *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGLyricsPiPEngine *engine = weakSelf;
        if (engine.attempt != attempt) return; // a stale block must not clear the new attempt's flag
        engine.retryPending = NO;
        [engine refresh];
    });
}

- (void)enqueue:(NSArray<NSString *> *)content generation:(NSUInteger)generation {
    AVSampleBufferDisplayLayer *layer = self.displayLayer;
    if (!layer.readyForMoreMediaData) { [self scheduleRetry]; return; }
    CVPixelBufferRef pixel = NULL;
    // The allocation threshold is a hard bound even if the system retains enqueued frames.
    NSDictionary *aux = @{(__bridge NSString *)kCVPixelBufferPoolAllocationThresholdKey: @3};
    CVReturn result = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, _pool,
                                                                          (__bridge CFDictionaryRef)aux, &pixel);
    if (result == kCVReturnWouldExceedAllocationThreshold) { [self scheduleRetry]; return; }
    if (result != kCVReturnSuccess) { [self fail:@"pixel buffer allocation failed"]; return; }
    if (CVPixelBufferLockBaseAddress(pixel, 0) != kCVReturnSuccess) {
        CVPixelBufferRelease(pixel);
        [self fail:@"pixel buffer lock failed"];
        return;
    }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pixel), kWidth, kHeight, 8,
        CVPixelBufferGetBytesPerRow(pixel), space, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(space);
    if (context) {
        CGContextSetRGBFillColor(context, 0.04, 0.04, 0.05, 1);
        CGContextFillRect(context, CGRectMake(0, 0, kWidth, kHeight));
        drawText(context, content[0], CGRectMake(24, 156, 592, 180), 40, 1);
        drawText(context, content[1], CGRectMake(24, 76, 592, 76), 26, 0.65);
        drawText(context, content[2], CGRectMake(24, 10, 592, 58), 17, 0.7);
        CGContextRelease(context);
    }
    CVPixelBufferUnlockBaseAddress(pixel, 0);
    if (!context) { CVPixelBufferRelease(pixel); [self fail:@"bitmap context creation failed"]; return; }
    CMVideoFormatDescriptionRef format = NULL;
    CMSampleBufferRef sample = NULL;
    OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixel, &format);
    CMSampleTimingInfo timing = {kCMTimeInvalid, CMTimeMakeWithSeconds(_position, 1000), kCMTimeInvalid};
    if (status == noErr) status = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, pixel, format, &timing, &sample);
    CVPixelBufferRelease(pixel);
    if (format) CFRelease(format);
    if (status != noErr || !sample) { [self fail:@"sample buffer creation failed"]; return; }
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sample, true);
    CFMutableDictionaryRef attachment = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
    CFDictionarySetValue(attachment, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
    if (generation == _generation && (_active || _starting)) {
        [layer enqueueSampleBuffer:sample];
        _shown = content;
    }
    CFRelease(sample);
}

- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)controller {
    if (controller != _pip || !_starting) { [controller stopPictureInPicture]; return; }
    _starting = NO;
    _active = YES;
    _host.alpha = 0; // the real layer stays attached; only its inline preview goes away
    [self announce];
    [self refresh];
}

- (void)pictureInPictureController:(AVPictureInPictureController *)controller failedToStartPictureInPictureWithError:(NSError *)error {
    if (controller == _pip && _starting) [self fail:[NSString stringWithFormat:@"start failed under Spotify's audio session: %@", error]];
}

- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)controller {
    if (controller != _pip) return;
    [self finish]; // closing the window never sends a player command
    [self showRestoredCredit];
}

- (void)pictureInPictureControllerWillStopPictureInPicture:(AVPictureInPictureController *)controller {
    if (controller == _pip) _stopping = YES;
}

- (BOOL)pictureInPictureControllerShouldProhibitBackgroundAudioPlayback:(AVPictureInPictureController *)controller {
    return NO; // Spotify's audio must survive closing the PiP window.
}

- (void)showRestoredCredit {
    if (!_restoreCredit || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    UIViewController *presenter = _window.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    if (!presenter || presenter.isBeingDismissed) return;
    NSString *track = SGKaraokePlayingTrack();
    NSString *credit = track.length ? SGLyricsCreditFor(track) : nil;
    NSArray<SGLyricsLink *> *links = SGLyricsCreditLinks(credit);
    _restoreCredit = NO;
    if (!links.count) return;
    // Return to Spotify first; never launch an uploader's URL merely because PiP was restored.
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:credit message:nil preferredStyle:UIAlertControllerStyleAlert];
    __weak UIWindow *window = _window;
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.lyrics.pip.credit_links", @"View source credits")
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            if (window) SGLyricsOpenCreditLinks(links, window);
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    SGPresentDark(alert);
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)pictureInPictureController:(AVPictureInPictureController *)controller
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:(void (^)(BOOL restored))completionHandler {
    // The owning Spotify window never depended on a lyrics page remaining alive.
    if (controller == _pip) _restoreCredit = YES;
    completionHandler(YES);
}

- (void)pictureInPictureController:(AVPictureInPictureController *)controller setPlaying:(BOOL)playing {
    if (controller != _pip || _stopping) return;
    id<SPTPlayer> player = SGKaraokePlayer();
    SPTPlayerState *state = player.state;
    if (!state) return;
    if (playing && state.isPaused) [player resume:nil];
    else if (!playing && !state.isPaused) [player pause:nil];
    [self scheduleRefresh];
}

- (BOOL)pictureInPictureControllerIsPlaybackPaused:(AVPictureInPictureController *)controller {
    return controller != _pip || !_playing;
}

- (CMTimeRange)pictureInPictureControllerTimeRangeForPlayback:(AVPictureInPictureController *)controller {
    // Finite, track-relative and always contains the layer's running time, even without a duration.
    double clock = _timebase ? CMTimeGetSeconds(CMTimebaseGetTime(_timebase)) : 0;
    double end = MAX(_duration, MAX(_position, isfinite(clock) ? clock : 0) + 1);
    return CMTimeRangeMake(kCMTimeZero, CMTimeMakeWithSeconds(end, 1000));
}

- (void)pictureInPictureController:(AVPictureInPictureController *)controller
    skipByInterval:(CMTime)interval completionHandler:(void (^)(void))completionHandler {
    double delta = CMTimeGetSeconds(interval);
    double duration = [(id<SPTPlayer>)SGKaraokePlayer() state].duration;
    if (controller == _pip && _timebase && isfinite(delta) && isfinite(duration) && duration > 0) {
        double target = MIN(duration, MAX(0, SGKaraokePositionMs() / 1000.0 + delta));
        NSInteger targetMs = (NSInteger)llround(target * 1000);
        [self resetFrames];
        SGKaraokeSeek(targetMs);
        // PiP reads the clock when completion runs; don't leave it at the pre-seek position
        // until Spotify reports the seek and the deferred refresh catches up.
        _position = targetMs / 1000.0;
        CMTimebaseSetTime(_timebase, CMTimeMake(targetMs, 1000));
        [_pip invalidatePlaybackState];
        [self scheduleRefresh];
    }
    completionHandler();
}

- (void)pictureInPictureController:(AVPictureInPictureController *)controller
    didTransitionToRenderSize:(CMVideoDimensions)newRenderSize {
    // A fixed, modest raster keeps the CPU and pool bounded at every system window size.
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_pip removeObserver:self forKeyPath:@"pictureInPicturePossible" context:kPossibleContext];
    [_timer invalidate];
    if (_pool) CVPixelBufferPoolRelease(_pool);
    if (_timebase) CFRelease(_timebase);
}
@end

__attribute__((constructor)) static void lyricsPiPLaunch(void) {
    @autoreleasepool { sg_enabled = SGFlag(SGKeyLyricsPiP, NO); }
}
