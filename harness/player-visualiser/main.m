// Asserts the Visualizer view offline (Redesigned/Player/PlayerVisualiser.m) under stubs for what it reads:
//   - the Lyrics style clears the words when its source changes to lyrics that are not synced (a kept-lines
//     notification for the playing track), instead of leaving the old source's line on screen;
//   - the display link asks for the screen's full rate whether or not the player's lyrics are open over the
//     hills or Reduce Motion is on, and the hills draw 60, 30 and 15 times a second in those three cases from a
//     120 Hz link's ticks.
// Exits 1 on any failure.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Lyrics/LyricsLook.h"
#import "Shared/AudioEffects/AudioEffects.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerEvents.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"
#import "Player.h"
#import "../harness-fail.h"

#pragma mark - the stubs

static NSString *gTrack = @"track-a";
static NSArray<SGKaraokeLine *> *gLines;
static NSInteger gPositionMs;
static BOOL gReduceMotion;

NSNotificationName const SGKaraokeLinesKeptNotification = @"harness.linesKept";
NSNotificationName const SGRNowPlayingArtworkDidChangeNotification = @"harness.artwork";
const NSTimeInterval SGRCrossfade = 0.35;

NSString *SGL(NSString *key, NSString *english) { return english; }
BOOL SGRReduceMotion(void) { return gReduceMotion; }
void SGRAnimate(SGRMotion motion, void (^animations)(void), void (^completion)(BOOL finished)) {
    animations();
    if (completion) completion(YES);
}
NSString *SGKaraokePlayingTrack(void) { return gTrack; }
NSArray<SGKaraokeLine *> *SGKaraokeLinesForTrack(NSString *trackID) { return [trackID isEqual:gTrack] ? gLines : nil; }
void SGKaraokeRequestLyrics(NSString *trackID) {}
NSInteger SGKaraokePositionMs(void) { return gPositionMs; }
NSInteger SGKaraokeDelayMs(void) { return 0; }
NSArray<SGKaraokeLine *> *SGRLyricsSampleLines(void) { return nil; }
NSInteger SGRLyricsSampleLength(void) { return 1; }
void SGAudioSetOutputReader(SGAudioOutputReader reader) {}
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {}
NSString *SGURIString(id uri) { return nil; }
CFTimeInterval SGPlayerTransitionEnds(void) { return 0; }
BOOL SGRPlayerIsTransitioning(void) { return NO; }
void SGRObservePlayerTransition(id owner, void (^changed)(id owner)) {}
UIImage *SGRNowPlayingArtwork(NSString **trackURI, NSString **identity) { return nil; }
BOOL SGPlayerMenuOffersAnimatedArtwork(void) { return NO; }
void SGPlayerMenuSetAnimatedArtwork(BOOL on) {}
SGRPlayerBackgroundKind SGRPlayerBackground(void) { return SGRPlayerBackgroundVisualiser; }
NSUInteger SGRSetPlayerBackground(SGRPlayerBackgroundKind kind) { return 0; }
SGRArtworkField *SGRPlayerField(void) { return nil; }
void SGRPlayerHoldField(void) {}
BOOL SGRPlayerLyricsOpen(void) { return NO; }
BOOL SGRPlayerMotionShowing(void) { return NO; }
// PlayerMotion.x's no-clip fallback and the shuffle and heat switches (Core/SGPrefs.m): all off, as unset.
BOOL SGHidden(NSString *key) { return NO; }
BOOL SGRPlayerAnimatedVisualiserOn(void) { return NO; }
void SGRPlayerReconcileFallbackSwitches(void) {}
BOOL SGRPlayerVisualiserFallbackWanted(void) { return NO; }

// A song that is playing, so the Lyrics style keeps its clock.
@implementation SPTPlayerState
- (BOOL)isPaused { return NO; }
@end
SPTPlayerState *SGPlayerState(void) {
    static SPTPlayerState *playing;
    if (!playing) playing = [SPTPlayerState new];
    return playing;
}

@implementation SGRPalette
+ (void)paletteForImage:(UIImage *)image request:(SGRPaletteRequest)request completion:(void (^)(SGRPalette *palette))completion {}
+ (void)tintForImage:(UIImage *)image surface:(UIColor *)surface strong:(BOOL)strong completion:(void (^)(UIColor *tint))completion {}
@end

#pragma mark - the harness

@protocol Probe <NSObject>
- (void)lyricsKept:(NSNotification *)note;
- (void)tick:(id)link;
- (void)setMoving:(BOOL)moving;
- (void)setBlurred:(BOOL)blurred animated:(BOOL)animated;
@end

// A window on a 120 Hz screen: a command line Mac Catalyst process has no scene to make a UIWindow in.
@interface FakeScreen : NSObject
@property (nonatomic) NSInteger maximumFramesPerSecond;
@end
@implementation FakeScreen
@end
@interface FakeWindow : NSObject
@property (nonatomic, strong) FakeScreen *screen;
@end
@implementation FakeWindow
@end

// The window the view reports while set; UIKit's own hierarchy code never sees it, as it would take it for a
// UIWindow, so it is set only around the calls that read the screen's rate.
static FakeWindow *gWindow;

static UIView *visualiser(void) {
    Class base = NSClassFromString(@"SGRVisualiserView");
    Class made = objc_allocateClassPair(base, "HarnessVisualiser", 0);
    class_addMethod(made, @selector(window), imp_implementationWithBlock(^id(id self) { return gWindow; }), "@@:");
    objc_registerClassPair(made);
    return [[made alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
}

// What -tick: reads of a display link.
@interface FakeLink : NSObject
@property (nonatomic) CFTimeInterval timestamp, duration;
@end
@implementation FakeLink
@end

static SGKaraokeLine *line(NSString *text, NSInteger start, NSInteger end, SGKaraokeTiming timing) {
    SGKaraokeWord *word = [SGKaraokeWord new];
    word.text = text;
    word.start = start;
    word.end = end;
    SGKaraokeLine *one = [SGKaraokeLine new];
    one.words = @[ word ];
    one.start = start;
    one.end = end;
    one.timing = timing;
    return one;
}

// The most visible label's text, nil when none shows.
static NSString *shownWords(UIView *view) {
    for (UILabel *label in [view valueForKey:@"_lyricLabels"]) {
        if (label.alpha > 0) return label.text;
    }
    return nil;
}

// How many of `ticks` ticks of a 120 Hz link the view draws on, counted by the clock it keeps for dt.
static NSUInteger drawsOf(UIView *view, NSUInteger ticks) {
    FakeLink *link = [FakeLink new];
    link.duration = 1.0 / 120;
    [view setValue:@0 forKey:@"_last"];
    NSUInteger draws = 0;
    CFTimeInterval before = 0;
    for (NSUInteger i = 0; i < ticks; i++) {
        link.timestamp = 100 + (double)i / 120;
        [(id<Probe>)view tick:link];
        CFTimeInterval after = [[view valueForKey:@"_last"] doubleValue];
        if (after != before) draws++;
        before = after;
    }
    return draws;
}

int main(void) {
    @autoreleasepool {
        [NSUserDefaults.standardUserDefaults setObject:@"builtin:lyrics" forKey:SGRKeyVisualiserStyle];
        gLines = @[ line(@"hold me close", 0, 3000, SGKaraokeTimingLine) ];
        gPositionMs = 1000;

        FakeWindow *window = [FakeWindow new];
        window.screen = [FakeScreen new];
        window.screen.maximumFramesPerSecond = 120;
        UIView *view = visualiser();

        // The synced line is on screen; the playing track's lyrics are then replaced by ones nothing times.
        HARNESS_CHECK([shownWords(view) isEqualToString:@"hold me close"]);
        gLines = @[ line(@"plain words", 0, 0, SGKaraokeTimingNone) ];
        [NSNotificationCenter.defaultCenter postNotificationName:SGKaraokeLinesKeptNotification object:@"track-a"];
        HARNESS_CHECK(shownWords(view) == nil);
        // Back to synced lyrics: the line returns.
        gLines = @[ line(@"hold me close", 0, 3000, SGKaraokeTimingLine) ];
        [NSNotificationCenter.defaultCenter postNotificationName:SGKaraokeLinesKeptNotification object:@"track-a"];
        HARNESS_CHECK([shownWords(view) isEqualToString:@"hold me close"]);

        // The link asks for the screen's full rate in every case.
        gWindow = window;
        NSInteger screenRate = window.screen.maximumFramesPerSecond;
        HARNESS_CHECK(screenRate == 120);
        id<Probe> probe = (id<Probe>)view;
        [probe setMoving:YES];
        CADisplayLink *link = [view valueForKey:@"_link"];
        HARNESS_CHECK(link != nil);
        HARNESS_CHECK(link.preferredFrameRateRange.maximum == screenRate && link.preferredFrameRateRange.preferred == screenRate);
        [probe setBlurred:YES animated:NO];
        [probe setMoving:YES];
        HARNESS_CHECK(link.preferredFrameRateRange.maximum == screenRate && link.preferredFrameRateRange.preferred == screenRate);
        [probe setBlurred:NO animated:NO];
        gReduceMotion = YES;
        [probe setMoving:YES];
        HARNESS_CHECK(link.preferredFrameRateRange.maximum == screenRate && link.preferredFrameRateRange.preferred == screenRate);
        gReduceMotion = NO;

        // The hills draw 60 times a second normally, 30 behind the player's lyrics and 15 with Reduce Motion.
        HARNESS_CHECK(drawsOf(view, 120) == 60);
        [probe setBlurred:YES animated:NO];
        HARNESS_CHECK(drawsOf(view, 120) == 30);
        [probe setBlurred:NO animated:NO];
        gReduceMotion = YES;
        HARNESS_CHECK(drawsOf(view, 120) == 15);
        gReduceMotion = NO;

        printf("player visualiser: all checks passed\n");
        return 0;
    }
}
