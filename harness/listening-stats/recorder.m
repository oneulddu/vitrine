// The production Logos recorder with fake player reports and an injected continuous clock.
#import "Shared/ListeningStats/ListeningStats.h"
#import "Shared/ListeningStats/SGPlayLog.h"
#import "Shared/Player/PlayerState.h"
#import <mach/mach_time.h>

#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAILED recorder line %d: %s\n", __LINE__, #c); exit(1); } } while (0)

static id<SGPlayerStateObserver> observer;
static uint64_t ticks;
uint64_t mach_continuous_time(void) { return ticks; }
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> value) { observer = value; }
BOOL SGEnabled(NSString *key) { return YES; }
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
    __block BOOL done = NO;
    [SGListeningLog() finishPendingWritesWithCompletion:^(NSError *error) {
        CHECK(!error); done = YES;
    }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!done && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    NSArray<SGPlay *> *plays = SGListeningLog().plays;
    CHECK(done && plays.count == 1);
    SGPlay *play = plays.firstObject;
    CHECK(play.ms == 40000 && [play.uri isEqual:@"spotify:track:first"]);
    CHECK([play.title isEqual:@"Late title"] && [play.artist isEqual:@"Late artist"] && [play.album isEqual:@"Late album"]);
    puts("recorder: metadata-only reports enrich exactly one forty-second play; unrelated reports do not overwrite it");
    return 0;
} }
