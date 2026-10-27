// Mac control-side integration: the production record owner, with player reports and audio setters
// stood in for. No GUI and no audio device are needed.
#import "Shared/Player/SpeedPitchSongs.h"
#import "Shared/Player/SpeedPitch.h"
#import <stdio.h>
#import <stdlib.h>

NSNotificationName const UIApplicationDidEnterBackgroundNotification = @"HarnessBackground";
static SGSpeedPitchSongs *owner;
static double speed = 1;
static float pitch, reverb;
static BOOL follows = YES, admitted = YES;
static SPTPlayerState *current;

@interface SPTPlayerTrack ()
@property (nonatomic, readwrite) id URI;
@end
@implementation SPTPlayerTrack
@synthesize URI;
@dynamic artistURI, artistName, trackTitle, metadata, provider;
@end
@interface SPTPlayerState ()
@property (nonatomic, readwrite) SPTPlayerTrack *track;
@end
@implementation SPTPlayerState
@synthesize track;
@dynamic sleepTimer, contextURI, options, isPaused, isPlaying, isLoading, position,
    positionAsOfTimestamp, timestamp, playbackSpeed, duration, future, reverse;
@end

NSString *SGURIString(id uri) {
    return [uri isKindOfClass:NSURL.class] ? [uri absoluteString] : uri;
}
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {}
SPTPlayerState *SGPlayerState(void) { return current; }
double SGPlayerSpeed(void) { return speed; }
float SGPlayerPitch(void) { return pitch; }
float SGPlayerReverb(void) { return reverb; }
BOOL SGPlayerPitchFollowsSpeed(void) { return follows; }
BOOL SGPlayerSpeedAllowed(void) { return admitted; }
BOOL SGPlayerPitchAvailable(void) { return admitted; }
void SGSetPlayerSpeed(double value) {
    if (!admitted) return;
    speed = value;
    [owner valuesChanged:@"speed"];
}
void SGSetPlayerPitch(float value) {
    if (!admitted) return;
    pitch = value;
    [owner valuesChanged:@"pitch"];
}
void SGSetPlayerPitchFollowsSpeed(BOOL value) {
    follows = value;
    [owner valuesChanged:@"follows"];
}
void SGPlayerSetReverb(float value) {
    reverb = value;
    [owner valuesChanged:@"reverb"];
}

static void check(BOOL ok, NSString *message) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static void play(id uri) {
    SPTPlayerTrack *track = [SPTPlayerTrack new];
    track.URI = uri;
    current = [SPTPlayerState new];
    current.track = track;
    [owner playerStateDidReport:current];
}
static void values(double s, float p, BOOL f, float r) {
    SGSetPlayerSpeed(s); SGSetPlayerPitch(p);
    SGSetPlayerPitchFollowsSpeed(f); SGPlayerSetReverb(r);
}
static void expect(double s, float p, BOOL f, float r, NSString *message) {
    check(speed == s && pitch == p && follows == f && reverb == r, message);
}
static void runFor(NSTimeInterval seconds) {
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}
static NSDictionary *records(NSUserDefaults *defaults) {
    return [defaults dictionaryForKey:@"spotifyglass.speedPitch.songs"];
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        check(argc == 3, @"expected suite and phase");
        NSString *suite = @(argv[1]), *phase = @(argv[2]);
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        owner = [[SGSpeedPitchSongs alloc] initWithDefaults:defaults];
        if ([phase isEqual:@"read"]) {
            // Speed/pitch restart at session defaults; persistent globals still hold the kept song.
            speed = 1; pitch = 0; follows = NO; reverb = 45;
            play(@"spotify:local:Art%20ist:Album:Song:123");
            check(owner.kept, @"local record survives a new process and encoding variant");
            expect(1.5, 3, NO, 45, @"relaunch applies all four saved controls");
            play(@"spotify:track:unkept-after-launch");
            expect(0.75, -2, YES, 5, @"separate-process relaunch restores the original baseline");
            play(@"spotify:local:Art+ist:Album:Song:123");
            owner = [[SGSpeedPitchSongs alloc] initWithDefaults:defaults];
            play(@"spotify:track:first-unkept");
            expect(0.75, -2, YES, 5, @"first unkept track after relaunch restores stored baseline");
            puts("PASS relaunch persistence");
            return 0;
        }
        [defaults removePersistentDomainForName:suite];
        owner = [[SGSpeedPitchSongs alloc] initWithDefaults:defaults];
        values(0.75, -2, YES, 5);
        play(@"spotify:track:a");
        check(!owner.kept, @"a new song is opt-in");
        [owner setKept:YES];
        check(records(defaults)[@"spotify:track:a"] != nil, @"keep writes immediately");
        values(1.5, 3, NO, 45);
        check([records(defaults)[@"spotify:track:a"][@"speed"] doubleValue] == 0.75,
              @"slider updates do not write immediately");
        runFor(0.30);
        SGSetPlayerPitch(4);
        runFor(0.30);
        check([records(defaults)[@"spotify:track:a"][@"pitch"] floatValue] == -2,
              @"an obsolete generation cannot flush a newer edit");
        runFor(0.30);
        check([records(defaults)[@"spotify:track:a"][@"pitch"] floatValue] == 4,
              @"latest values flush after the quiet interval");
        play(@"spotify:track:b");
        expect(0.75, -2, YES, 5, @"leaving kept restores non-default prior values");
        play([NSURL URLWithString:@"spotify:track:a"]);
        expect(1.5, 4, NO, 45, @"returning applies four controls");
        owner = [[SGSpeedPitchSongs alloc] initWithDefaults:defaults];
        play(@"spotify:track:c");
        expect(0.75, -2, YES, 5, @"relaunch restores the original baseline");
        play(@"spotify:track:a");
        SGSetPlayerPitch(6);
        play(@"spotify:track:b");
        check([records(defaults)[@"spotify:track:a"][@"pitch"] floatValue] == 6,
              @"skipping flushes a pending edit");
        [owner setKept:YES];
        values(1.25, -4, NO, 20);
        play(@"spotify:track:a");
        expect(1.5, 6, NO, 45, @"kept to kept applies the next record");
        owner = [[SGSpeedPitchSongs alloc] initWithDefaults:defaults];
        play(@"spotify:track:b");
        expect(1.25, -4, NO, 20, @"relaunch into another kept song applies its record");
        play(@"spotify:track:c");
        expect(0.75, -2, YES, 5, @"kept chain across relaunch restores original baseline");
        play(@"spotify:track:a");
        SGSetPlayerPitch(7);
        [owner setKept:NO];
        check(records(defaults)[@"spotify:track:a"] == nil, @"unkeep removes immediately");
        expect(0.75, -2, YES, 5, @"unkeep restores the baseline");
        runFor(0.60);
        check(records(defaults)[@"spotify:track:a"] == nil, @"pending edit cannot resurrect unkept song");
        play(@"spotify:track:b");
        admitted = NO;
        play(@"spotify:track:c");
        check([defaults objectForKey:@"spotifyglass.speedPitch.baseline"] != nil,
              @"baseline remains durable until unavailable controls restore");
        admitted = YES;
        [owner playerStateDidReport:current];
        expect(0.75, -2, YES, 5, @"restore waits for admission without changing admission");
        check([defaults objectForKey:@"spotifyglass.speedPitch.baseline"] == nil,
              @"completed restoration clears the durable baseline");
        admitted = NO;
        play(@"spotify:track:b");
        check(speed == 0.75 && pitch == -2, @"unavailable speed and pitch stay untouched");
        SGPlayerSetReverb(35);
        admitted = YES;
        [owner playerStateDidReport:current];
        expect(1.25, -4, NO, 35, @"delayed apply retains saved pitch and a newer reverb edit");
        play(nil);
        expect(0.75, -2, YES, 5, @"no-track restores the prior controls");
        check(!owner.hasSong, @"no-track cannot be kept");

        play(@"spotify:track:override");
        [owner setKept:YES];
        values(1.5, 3, NO, 45);
        admitted = NO;
        [owner setKept:NO];
        SGPlayerSetReverb(65);
        SGSetPlayerPitchFollowsSpeed(NO);
        check([[defaults dictionaryForKey:@"spotifyglass.speedPitch.baseline"]
               isEqual:@{@"speed": @0.75, @"pitch": @(-2)}],
              @"partial restore retains only outstanding controls, not deliberate global edits");
        play(@"spotify:track:another-unkept");
        expect(1.5, 3, NO, 65, @"unkept transition preserves edits made during unavailable restoration");
        play(@"spotify:track:b");
        play(@"spotify:track:another-unkept");
        expect(1.5, 3, NO, 65, @"a kept interruption restores the newly chosen global controls");
        owner = [[SGSpeedPitchSongs alloc] initWithDefaults:defaults];
        speed = 1; pitch = 0; // Reverb and pitch-follow remain at their persisted user choices.
        play(@"spotify:track:unkept-after-partial-relaunch");
        expect(1, 0, NO, 65, @"relaunch does not reapply superseded global controls");
        admitted = YES;
        SGSetPlayerSpeed(1.75);
        check([[defaults dictionaryForKey:@"spotifyglass.speedPitch.baseline"] isEqual:@{@"pitch": @(-2)}],
              @"deliberate speed change drops only its outstanding restore");
        [owner playerStateDidReport:current];
        expect(1.75, -2, NO, 65, @"partial baseline restores remaining pitch after relaunch");
        check([defaults objectForKey:@"spotifyglass.speedPitch.baseline"] == nil,
              @"last outstanding restoration clears the partial baseline");
        values(0.75, -2, YES, 5);

        // Independent timestamp fixture: eviction must use timestamps, not insertion or key order.
        NSMutableDictionary *many = [NSMutableDictionary dictionary];
        for (NSUInteger i = 0; i < 200; i++) {
            NSString *key = [NSString stringWithFormat:@"spotify:track:%03lu", (unsigned long)i];
            many[key] = @{@"speed": @1, @"pitch": @0, @"follows": @YES, @"reverb": @0,
                          @"timestamp": @(i == 73 ? 0 : i + 1)};
        }
        [defaults setObject:many forKey:@"spotifyglass.speedPitch.songs"];
        owner = [[SGSpeedPitchSongs alloc] initWithDefaults:defaults];
        play(@"spotify:track:new");
        [owner setKept:YES];
        NSDictionary *capped = records(defaults);
        check(capped.count == 200 && !capped[@"spotify:track:073"] && capped[@"spotify:track:000"],
              @"200-record cap evicts oldest timestamp");

        NSString *local = @"spotify:local:Art+ist:Album:Song:123";
        NSString *key = SGSpeedPitchSongIdentifier(local);
        check([key isEqual:SGSpeedPitchSongIdentifier(@"spotify:local:Art%20ist:Album:Song:123")]
              && [key hasPrefix:@"local:"] && key.length == 38, @"local form encoding has a short stable identifier");
        check(![key isEqual:SGSpeedPitchSongIdentifier(@"spotify:local:Art+ist:Album:Other:123")],
              @"different local recordings remain distinct");
        check(SGSpeedPitchSongIdentifier(@"spotify:local:bad") == nil, @"malformed local URI cannot be kept");
        play(local);
        [owner setKept:YES];
        check(records(defaults)[key] != nil, @"local keep writes immediately");
        values(1.5, 3, NO, 45);
        [owner flush];
        check([defaults synchronize], @"persist test suite before separate-process relaunch");
        puts("PASS record, apply, restore, unkeep, eviction, coalescing, admission, local identifier");
    }
    return 0;
}
