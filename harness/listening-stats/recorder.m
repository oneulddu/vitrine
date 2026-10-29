// The production Logos recorder with fake player reports and an injected continuous clock.
#import "Shared/ListeningStats/ListeningStats.h"
#import "Shared/ListeningStats/SGPlayLog.h"
#import "Shared/Player/PlayerState.h"
#import "Core/SGPrefs.h"
#import <mach/mach_time.h>

#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAILED recorder line %d: %s\n", __LINE__, #c); exit(1); } } while (0)

static id<SGPlayerStateObserver> observer;
static uint64_t ticks;
uint64_t mach_continuous_time(void) { return ticks; }
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> value) { observer = value; }
NSString *SGURIString(id uri) { return [uri isKindOfClass:NSString.class] ? uri : [uri absoluteString]; }

@interface RecorderTrack : NSObject
@property(nonatomic, copy) NSString *URI, *trackTitle, *artistName;
@property(nonatomic, copy) NSDictionary *metadata;
@end
@implementation RecorderTrack @end
@interface RecorderState : NSObject
@property(nonatomic, strong) RecorderTrack *track;
@property(nonatomic) BOOL isPlaying, isPaused, isLoading;
@property(nonatomic) double duration;
@end
@implementation RecorderState @end

static SPTPlayerState *state(NSString *uri, NSString *title, NSString *artist) {
    RecorderTrack *track = [RecorderTrack new];
    track.URI = uri; track.trackTitle = title; track.artistName = artist;
    track.metadata = artist ? @{@"artist_name": artist, @"album_title": @"Late album"} : @{};
    RecorderState *state = [RecorderState new];
    state.track = track; state.isPlaying = YES; state.duration = 200;
    return (SPTPlayerState *)state;
}
static void setElapsed(uint64_t seconds) {
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    ticks = seconds * NSEC_PER_SEC * timebase.denom / timebase.numer;
}

static void recording(BOOL enabled) {
    SGSetEnabled(SGKeyListeningStats, enabled);
    // Deliver the defaults contract deterministically, including on a worker.
    // An automatic duplicate notification must not reset an enabled interval.
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
}

static NSArray<SGPlay *> *recordedPlays(void) {
    __block BOOL done = NO;
    [SGListeningLog() finishPendingWritesWithCompletion:^(NSError *error) {
        CHECK(!error); done = YES;
    }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!done && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    CHECK(done);
    return SGListeningLog().plays;
}

static void drainMain(void) {
    __block BOOL applied = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ applied = YES; });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!applied && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    CHECK(applied);
}

int main(void) { @autoreleasepool {
    CHECK(observer && [observer respondsToSelector:@selector(playerStateDidReport:)]);
    setElapsed(100);
    [observer playerStateDidChange:state(@"spotify:track:first", nil, nil)];
    setElapsed(120);
    [observer playerStateDidReport:state(@"spotify:track:unrelated", @"Wrong title", @"Wrong artist")];
    [observer playerStateDidReport:state(@"spotify:track:first", @"Late title", @"Late artist")];
    setElapsed(140);
    SPTPlayerState *next = state(@"spotify:track:second", @"Next title", @"Next artist");
    [observer playerStateDidReport:next]; // PlayerState reports before announcing the transition
    [observer playerStateDidChange:next];
    NSArray<SGPlay *> *plays = recordedPlays();
    CHECK(plays.count == 1);
    SGPlay *play = plays.firstObject;
    CHECK(play.ms == 40000 && [play.uri isEqual:@"spotify:track:first"]);
    CHECK([play.title isEqual:@"Late title"] && [play.artist isEqual:@"Late artist"] && [play.album isEqual:@"Late album"]);
    puts("recorder: metadata-only reports enrich exactly one forty-second play; unrelated reports do not overwrite it");

    // MEDIA-01: off -> play forty seconds -> pause -> on -> skip saves nothing.
    recording(NO);
    [observer playerStateDidChange:state(@"spotify:track:disabled", @"Disabled", @"Artist")];
    setElapsed(180);
    RecorderState *paused = (RecorderState *)state(@"spotify:track:disabled", @"Disabled", @"Artist");
    paused.isPaused = YES;
    [observer playerStateDidChange:(SPTPlayerState *)paused];
    recording(YES);
    [observer playerStateDidChange:state(@"spotify:track:enabled", @"Enabled", @"Artist")];
    CHECK(recordedPlays().count == 1);
    puts("recorder: disabled listening is not saved by enabling while paused");

    setElapsed(220);
    [observer playerStateDidChange:state(@"spotify:track:waiting", @"Waiting", @"Artist")];
    plays = recordedPlays();
    CHECK(plays.count == 2 && plays.lastObject.ms == 40000 &&
          [plays.lastObject.uri isEqual:@"spotify:track:enabled"]);
    puts("recorder: a qualifying play after enabling still records");

    // Enabling while already playing must not wait for another player callback.
    recording(NO);
    [observer playerStateDidChange:state(@"spotify:track:in-progress", @"In progress", @"Artist")];
    setElapsed(260);
    recording(YES);
    setElapsed(280);
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"harness.unrelated"];
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
    setElapsed(300);
    [observer playerStateDidChange:state(@"spotify:track:before-off", @"Before off", @"Artist")];
    plays = recordedPlays();
    CHECK(plays.count == 3 && plays.lastObject.ms == 40000 &&
          [plays.lastObject.uri isEqual:@"spotify:track:in-progress"]);
    puts("recorder: enabling mid-play starts at the boundary; unrelated preferences do not split it");

    setElapsed(340);
    recording(NO);
    plays = recordedPlays();
    CHECK(plays.count == 4 && plays.lastObject.ms == 40000 &&
          [plays.lastObject.uri isEqual:@"spotify:track:before-off"]);
    setElapsed(400);
    recording(YES);
    setElapsed(410);
    [observer playerStateDidChange:state(@"spotify:track:worker", @"Worker", @"Artist")];
    CHECK(recordedPlays().count == 4);
    puts("recorder: disabling finishes enabled time; re-enabling resets the threshold");

    // Main is busy for a worker's off/on pair. Neither notification may wait
    // for main, and the captured values/times must retain the disabled gap.
    dispatch_semaphore_t posted = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        setElapsed(420);
        recording(NO);
        setElapsed(460);
        recording(YES);
        dispatch_semaphore_signal(posted);
    });
    CHECK(dispatch_semaphore_wait(posted, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0);
    drainMain();
    setElapsed(500);
    [observer playerStateDidChange:state(@"spotify:track:last", @"Last", @"Artist")];
    plays = recordedPlays();
    CHECK(plays.count == 5 && plays.lastObject.ms == 40000 &&
          [plays.lastObject.uri isEqual:@"spotify:track:worker"]);
    puts("recorder: worker-thread off/on notifications preserve the gap without blocking on main");

    // A worker captures YES while main is busy. Main then switches recording
    // off synchronously, before draining that older YES from the main queue.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
        dispatch_semaphore_signal(posted);
    });
    CHECK(dispatch_semaphore_wait(posted, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0);
    setElapsed(510);
    recording(NO);
    drainMain();
    setElapsed(550);
    [observer playerStateDidChange:state(@"spotify:track:still-off", @"Still off", @"Artist")];
    CHECK(recordedPlays().count == 5);
    puts("recorder: an older queued YES cannot override a synchronous NO or save disabled listening");
    return 0;
} }
