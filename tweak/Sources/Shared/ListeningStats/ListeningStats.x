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
#import <stdatomic.h>

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
    SPTPlayerState *_state;
    BOOL _recordingEnabled;
}

- (instancetype)init {
    if ((self = [super init])) _recordingEnabled = SGEnabled(SGKeyListeningStats);
    return self;
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
    if (_play && _play.title.length && _play.artist.length && SGPlayCounts(_clock.listenedSeconds, _duration)) {
        _play.end = (int64_t)_clock.endedAt;
        _play.ms = (int64_t)(_clock.listenedSeconds * 1000);
        [SGListeningLog() record:_play];
    }
    _play = nil;
    _clock = nil;
}

- (void)playerStateDidReport:(SPTPlayerState *)state {
    _state = state;
    if ([SGURIString(state.track.URI) isEqualToString:_play.uri]) [self fill:state];
}

- (void)updateState:(SPTPlayerState *)state elapsed:(NSTimeInterval)elapsed at:(NSTimeInterval)now {
    _state = state;
    if (!_recordingEnabled) return;
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

- (void)playerStateDidChange:(SPTPlayerState *)state {
    [self updateState:state elapsed:continuousSeconds() at:NSDate.date.timeIntervalSince1970];
}

// Only enabled intervals own a play. Finish the old interval before changing
// consent, then start afresh from the latest state without waiting for a report.
- (void)recordingChanged:(BOOL)enabled elapsed:(NSTimeInterval)elapsed at:(NSTimeInterval)now {
    if (enabled == _recordingEnabled) return;
    [_clock setPlaying:NO elapsed:elapsed at:now];
    [self finish];
    _recordingEnabled = enabled;
    if (enabled) [self updateState:_state elapsed:elapsed at:now];
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
    static atomic_uint_fast64_t notificationRevision;
    // Accessed only on main, including when the enabled value did not change.
    static uint_fast64_t appliedRevision;
    recorder = [SGPlayRecorder new];
    SGAddPlayerStateObserver(recorder);
    [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            // Invalidate before reading: defaults observers have no ordering.
            // Capture each transition on the posting thread; a later main-queue
            // read could miss an off/on pair while main was busy.
            uint_fast64_t revision = atomic_fetch_add_explicit(&notificationRevision, 1, memory_order_relaxed) + 1;
            SGPrefsChanged();
            BOOL enabled = SGEnabled(SGKeyListeningStats);
            NSTimeInterval elapsed = continuousSeconds();
            NSTimeInterval now = NSDate.date.timeIntervalSince1970;
            dispatch_block_t apply = ^{
                // Main can apply a newer notification synchronously before a
                // worker's queued snapshot arrives. Never replay the older one.
                if (revision <= appliedRevision) return;
                appliedRevision = revision;
                [recorder recordingChanged:enabled elapsed:elapsed at:now];
            };
            if (NSThread.isMainThread) apply();
            else dispatch_async(dispatch_get_main_queue(), apply);
        }];
    [NSNotificationCenter.defaultCenter addObserver:recorder selector:@selector(terminate) name:UIApplicationWillTerminateNotification object:nil];
}
