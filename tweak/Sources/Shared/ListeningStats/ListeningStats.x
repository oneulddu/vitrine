// ListeningStats.h says what Listening stats is. This is the recording: PlayerState's observer is told
// when the track or playing changes, never the position, so a play's length is the continuous time it
// spent playing, and it is written down when the next track takes over.
//
// ponytail: a track on repeat one never changes the state's track, so its replays are not counted, and a
// play cut off by Spotify being killed is lost; position polling would catch both.
#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"
#import "ListeningStats.h"
#import "SGPlayLog.h"
#import <mach/mach_time.h>

static NSTimeInterval continuousSeconds(void) {
    static mach_timebase_info_data_t timebase;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ mach_timebase_info(&timebase); });
    return (double)mach_continuous_time() * timebase.numer / timebase.denom / NSEC_PER_SEC;
}

SGPlayLog *SGListeningLog(void) {
    static SGPlayLog *log;
    if (!log) {
        NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
        log = [[SGPlayLog alloc] initWithPath:[support stringByAppendingPathComponent:@"Vitrine/Listening.tsv"]];
    }
    return log;
}

static NSString *stringIn(id value) {
    return [value isKindOfClass:NSString.class] ? value : nil;
}

@interface SGPlayRecorder : NSObject <SGPlayerStateObserver>
@end

@implementation SGPlayRecorder {
    SGPlay *_play;
    double _duration;
    SGPlayClock *_clock;
}

// Songs and local files; not ads, episodes or the silence between.
static BOOL isMusic(NSString *uri) {
    return [uri hasPrefix:@"spotify:track:"] || [uri hasPrefix:@"spotify:local:"];
}

// The metadata can come after the track does, so what is missing is filled in on every report.
- (void)fill:(SPTPlayerState *)state {
    SPTPlayerTrack *track = state.track;
    NSDictionary *metadata = [track respondsToSelector:@selector(metadata)] ? track.metadata : nil;
    if (!_play.title.length) _play.title = stringIn(track.trackTitle) ?: stringIn(metadata[@"title"]) ?: @"";
    if (!_play.artist.length) _play.artist = stringIn(metadata[@"artist_name"]) ?: stringIn(track.artistName) ?: @"";
    if (!_play.album.length) _play.album = stringIn(metadata[@"album_title"]) ?: @"";
    if (_duration <= 0) _duration = state.duration;
}

- (void)finish {
    if (_play && _play.title.length && _play.artist.length && SGPlayCounts(_clock.listenedSeconds, _duration) && SGEnabled(SGKeyListeningStats)) {
        _play.end = (int64_t)_clock.endedAt;
        _play.ms = (int64_t)(_clock.listenedSeconds * 1000);
        [SGListeningLog() record:_play];
    }
    _play = nil;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSTimeInterval elapsed = continuousSeconds();
    [_clock setPlaying:NO elapsed:elapsed at:now];
    NSString *uri = SGURIString(state.track.URI);
    if (![uri isEqualToString:_play.uri]) {
        [self finish];
        if (isMusic(uri)) {
            _play = [SGPlay new];
            _play.uri = uri;
            _duration = 0;
            _clock = [SGPlayClock new];
        }
    }
    if (!_play) return;
    [self fill:state];
    BOOL loading = [state respondsToSelector:@selector(isLoading)] && state.isLoading;
    [_clock setPlaying:state.isPlaying && !state.isPaused && !loading elapsed:elapsed at:now];
}

- (void)terminate {
    [_clock setPlaying:NO elapsed:continuousSeconds() at:NSDate.date.timeIntervalSince1970];
    [self finish];
    if (![SGListeningLog() drainForTermination])
        NSLog(@"[spotifyglass] history: final recorder write not confirmed before termination");
}

@end

%ctor {
    static SGPlayRecorder *recorder;
    recorder = [SGPlayRecorder new];
    SGAddPlayerStateObserver(recorder);
    [NSNotificationCenter.defaultCenter addObserver:recorder selector:@selector(terminate) name:UIApplicationWillTerminateNotification object:nil];
}
