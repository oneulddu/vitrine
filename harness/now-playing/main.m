// Checks what reaches the system's now playing through the mod's two hooks of the setter,
// Shared/Player/NowPlayingExtras.x and Shared/LockScreenLyrics/LockScreenLyrics.x, built as the tweak
// builds them. The system's setter and getter are replaced underneath both (this file links first, so its
// constructor runs before their %ctors), and Karaoke is a stub with two lines. Run with LSL=1 for lock
// screen lyrics on, without it for off; it exits non-zero on the first check that fails.
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>
#include <stdlib.h>
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/NowPlayingExtras.h"
#import "Headers/SPTPlayer.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
#import "artwork.h"

#pragma mark - the system, underneath

static NSDictionary *sg_system;   // what the system was last given
static NSUInteger sg_sets;

static void systemSet(id self, SEL _cmd, NSDictionary *info) {
    sg_system = info;
    sg_sets++;
}

static NSDictionary *systemGet(id self, SEL _cmd) {
    return sg_system;
}

__attribute__((constructor)) static void underneath(void) {
    Class center = MPNowPlayingInfoCenter.class;
    class_replaceMethod(center, @selector(setNowPlayingInfo:), (IMP)systemSet, "v@:@");
    class_replaceMethod(center, @selector(nowPlayingInfo), (IMP)systemGet, "@@:");
}

#pragma mark - stubs

// These preference stubs read live values or fallbacks, so there is no cache to invalidate.
void SGPrefsChanged(void) {}

BOOL SGFlag(NSString *key, BOOL fallback) {
    return [key isEqual:SGKeyLockScreenLyrics] ? getenv("LSL") != NULL : fallback;
}

@implementation SPTPlayerTrack {
@public
    NSString *_title;
    NSString *_uri;
    NSDictionary *_metadata;
}
- (NSString *)trackTitle { return _title; }
- (id)URI { return _uri; }
- (NSDictionary *)metadata { return _metadata ?: @{}; }
- (NSString *)artistName { return @"Artist"; }
@end

@implementation SPTPlayerState {
@public
    SPTPlayerTrack *_track;
}
- (SPTPlayerTrack *)track { return _track; }
- (BOOL)isPaused { return YES; }
- (NSArray *)future { return nil; }
@end

@interface SGStubPlayer : NSObject
@property (nonatomic) SPTPlayerState *state;
@end
@implementation SGStubPlayer
@end

static SGStubPlayer *sg_player;
static NSArray<SGKaraokeLine *> *sg_lines;
static void (^sg_afterTickSnapshot)(void);
static NSUInteger sg_lyricReads;

id SGKaraokePlayer(void) {
    if (NSThread.isMainThread) {
        sg_lyricReads++;
        void (^gate)(void) = sg_afterTickSnapshot;
        sg_afterTickSnapshot = nil;
        if (gate) gate();
    }
    return sg_player;
}
NSString *SGKaraokePlayingTrack(void) { return sg_player.state.track.URI; }
NSArray<SGKaraokeLine *> *SGKaraokeLinesForTrack(NSString *trackID) { return sg_lines; }
void SGKaraokeRequestLyrics(NSString *trackID) {}
// The lines are there from the start, so nothing is posted under it.
NSNotificationName const SGKaraokeLinesKeptNotification = @"harness.karaokeLinesKept";
NSInteger SGKaraokeDelayMs(void) { return [NSUserDefaults.standardUserDefaults integerForKey:SGKeyLyricsDelay]; }
// Only the translation check selects the translated artist row.
static BOOL sg_showTranslation;
NSInteger SGInt(NSString *key, NSInteger fallback) {
    return [key isEqual:SGKeyLockScreenLyricsLine] && sg_showTranslation ? SGLockScreenLyricsLineTranslation : fallback;
}
NSString *SGLyricsGeminiLanguage(void) { return @"en"; }
void SGLyricsSyncSavedTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines) {}
void SGLyricsLoadTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines,
                             BOOL (^current)(void), void (^done)(void)) {
    dispatch_async(dispatch_get_main_queue(), ^{ if (current()) done(); });
}
void SGRAutoTranslateWithoutView(NSString *track, NSArray<SGKaraokeLine *> *lines, BOOL (^mayContinue)(void), void (^loaded)(void)) {
    dispatch_async(dispatch_get_main_queue(), ^{ if (mayContinue()) loaded(); });
}
NSNotificationName const SGLyricsTranslationSavedNotification = @"spotifyglass.lyricsTranslationSaved";

SGKaraokeLine *lineOf(NSString *text, NSInteger start, NSInteger end) {
    SGKaraokeWord *word = [SGKaraokeWord new];
    word.text = text;
    word.start = start;
    word.end = end;
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.words = @[word];
    line.start = start;
    line.end = end;
    line.timing = SGKaraokeTimingWords;
    return line;
}

#pragma mark - checks

static int failures;

void check(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "ok  " : "FAIL", what.UTF8String);
    if (!ok) failures++;
}

void runFor(NSTimeInterval seconds) {
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

SPTPlayerState *harnessState(NSString *uri, NSString *title) {
    SPTPlayerTrack *track = [SPTPlayerTrack new];
    track->_uri = uri;
    track->_title = title;
    SPTPlayerState *state = [SPTPlayerState new];
    state->_track = track;
    sg_player.state = state;
    return state;
}
void harnessLines(NSArray *lines) { sg_lines = lines; }
void harnessMetadata(NSDictionary *metadata) { sg_player.state.track->_metadata = metadata; }
NSDictionary *harnessSystem(void) { return sg_system; }
NSUInteger harnessSets(void) { return sg_sets; }

static NSDictionary *spotifyInfo(NSString *title, double elapsed, double rate) {
    return @{MPMediaItemPropertyTitle: title, MPMediaItemPropertyArtist: @"Artist",
             MPNowPlayingInfoPropertyElapsedPlaybackTime: @(elapsed), MPNowPlayingInfoPropertyPlaybackRate: @(rate)};
}

static double systemElapsed(void) {
    return [sg_system[MPNowPlayingInfoPropertyElapsedPlaybackTime] doubleValue];
}

// Lock screen lyrics: once the line is let go, the artist comes back with the clock moved on, and the
// extras' clock, which records what passes, is not pulled back by it either.
static void progressBar(void) {
    MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
    // Rate 4, so the 4 s break after the line's end comes in about a second of wall time.
    const double rate = 4;
    CFAbsoluteTime setAt = CFAbsoluteTimeGetCurrent();
    center.nowPlayingInfo = spotifyInfo(@"Song", 0, rate);
    check([sg_system[MPMediaItemPropertyArtist] isEqual:@"Hello"], @"the line sung shows in place of the artist");
    runFor(1.6);
    double expected = rate * (CFAbsoluteTimeGetCurrent() - setAt);
    check([sg_system[MPMediaItemPropertyArtist] isEqual:@"Artist"], @"the artist comes back in the break");
    // The line is let go 4 s past its end at 0.1 s, so the info that lets it go is from 4.1 s on.
    check(systemElapsed() > 4.1 && systemElapsed() <= expected,
          [NSString stringWithFormat:@"the break's info is at %.2f s, not Spotify's 0", systemElapsed()]);
    SGNowPlayingSetExtras(@"haptics", @{MPNowPlayingInfoPropertyInternationalStandardRecordingCode: @"ISRC"}, @"Song");
    expected = rate * (CFAbsoluteTimeGetCurrent() - setAt);
    check(fabs(systemElapsed() - expected) < 1.5,
          [NSString stringWithFormat:@"an extra's resend is at %.2f s (expected about %.2f)", systemElapsed(), expected]);
    SGNowPlayingSetExtras(@"haptics", nil, nil);
}

// Lock screen translation: a translation longer than the row is cut by its own
// length, not the line's, and its pieces follow the line's clock.
static void translation(void) {
    sg_showTranslation = YES;
    MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
    NSArray<SGKaraokeLine *> *was = sg_lines;
    SGKaraokeLine *line = lineOf(@"Hola", 0, 4000);
    line.translation = @"This translation runs well past what the lock screen's artist row holds";
    sg_lines = @[line];
    center.nowPlayingInfo = spotifyInfo(@"Song", 0, 0);
    NSString *first = sg_system[MPMediaItemPropertyArtist];
    check(first.length > 0 && first.length <= 30 && [line.translation hasPrefix:first],
          [NSString stringWithFormat:@"the translation's first piece shows: \"%@\"", first]);
    center.nowPlayingInfo = spotifyInfo(@"Song", 3.9, 0);
    NSString *last = sg_system[MPMediaItemPropertyArtist];
    check(last.length > 0 && last.length <= 30 && [line.translation hasSuffix:last],
          [NSString stringWithFormat:@"its last piece shows by the line's end: \"%@\"", last]);
    sg_lines = was;
    sg_showTranslation = NO;
}

static void pausedTrackDuringTick(void) {
    MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
    NSArray *saved = sg_lines;
    sg_lines = @[lineOf(@"A before", 0, 1000)];
    center.nowPlayingInfo = spotifyInfo(@"Song", 0, 1);
    sg_lines = @[lineOf(@"A after", 0, 1000)];
    __block BOOL gated = NO;
    sg_afterTickSnapshot = ^{
        gated = YES;
        dispatch_semaphore_t published = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            center.nowPlayingInfo = spotifyInfo(@"Paused B", 7, 0);
            dispatch_semaphore_signal(published);
        });
        check(dispatch_semaphore_wait(published, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0,
              @"paused B publishes off-main while A's tick is held after its snapshot");
    };
    [NSNotificationCenter.defaultCenter postNotificationName:SGKaraokeLinesKeptNotification object:nil];
    check(gated, @"the production lyric tick reaches the snapshot gate");
    runFor(.05);
    check([sg_system[MPMediaItemPropertyTitle] isEqual:@"Paused B"] && systemElapsed() == 7
          && [sg_system[MPNowPlayingInfoPropertyPlaybackRate] doubleValue] == 0,
          @"draining main restores paused B after A's stale resend");
    NSUInteger reads = sg_lyricReads;
    runFor(.35);
    check(sg_lyricReads == reads, @"paused B leaves no timer polling the lyric player");
    sg_lines = saved;
}

// Two tracks with one title: what the first had must not stay on the second's info once it is cleared.
static void sameTitle(void) {
    MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
    NSString *key = MPNowPlayingInfoPropertyInternationalStandardRecordingCode;
    center.nowPlayingInfo = spotifyInfo(@"Intro", 50, 0);
    SGNowPlayingSetExtras(@"lyrics", @{key: @"first"}, @"Intro");
    check([sg_system[key] isEqual:@"first"], @"the extra rides on its title's info");
    center.nowPlayingInfo = spotifyInfo(@"Intro", 0, 0);   // the next track, also called Intro
    check([sg_system[key] isEqual:@"first"], @"it rides on the next track of that title until cleared");
    SGNowPlayingSetExtras(@"lyrics", nil, nil);
    check(sg_system && !sg_system[key], @"cleared, it is taken off the info at once");
    check(fabs(systemElapsed()) < 0.01, @"the paused clock is kept");

    // Spotify building its next info from the one it reads back, so the extra comes along under a new title.
    SGNowPlayingSetExtras(@"lyrics", @{key: @"second"}, @"Intro");
    NSMutableDictionary *copied = [center.nowPlayingInfo mutableCopy];
    copied[MPMediaItemPropertyTitle] = @"Outro";
    center.nowPlayingInfo = copied;
    check([sg_system[key] isEqual:@"second"], @"copied, it rides on another title's info");
    SGNowPlayingSetExtras(@"lyrics", nil, nil);
    check(!sg_system[key], @"cleared, it comes off an info it was copied onto");

    // Nothing to take off: nothing is sent.
    SGNowPlayingSetExtras(@"lyrics", @{key: @"third"}, @"Intro");
    NSUInteger sets = sg_sets;
    SGNowPlayingSetExtras(@"lyrics", nil, nil);
    check(sg_sets == sets, @"cleared for another title, the info is not sent again");

    // Another owner's extra for the same title stays.
    center.nowPlayingInfo = spotifyInfo(@"Intro", 0, 0);
    SGNowPlayingSetExtras(@"haptics", @{@"other": @"kept"}, @"Intro");
    SGNowPlayingSetExtras(@"lyrics", @{key: @"fourth"}, @"Intro");
    SGNowPlayingSetExtras(@"lyrics", nil, nil);
    check(!sg_system[key] && [sg_system[@"other"] isEqual:@"kept"], @"another owner's extra stays on");
    SGNowPlayingSetExtras(@"haptics", nil, nil);
}

int main(void) {
    @autoreleasepool {
        SPTPlayerTrack *track = [SPTPlayerTrack new];
        track->_title = @"Song";
        track->_uri = @"track";
        SPTPlayerState *state = [SPTPlayerState new];
        state->_track = track;
        sg_player = [SGStubPlayer new];
        sg_player.state = state;
        sg_lines = @[lineOf(@"Hello", 0, 100), lineOf(@"Later", 60000, 61000)];
        BOOL lyrics = getenv("LSL") != NULL;
        printf("lock screen lyrics %s\n", lyrics ? "on" : "off");
        if (lyrics) progressBar();
        if (lyrics) translation();
        if (lyrics) pausedTrackDuringTick();
        sameTitle();
        artworkChecks();
        printf(failures ? "%d failed\n" : "all passed\n", failures);
        return failures ? 1 : 0;
    }
}
