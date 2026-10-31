#import <Foundation/Foundation.h>
#import "Shared/AutoMix/AutoMix.h"
#import "Shared/AutoMix/SGTransitionFactsInternal.h"
#import "Shared/Player/PlayerState.h"

// Real facts implementation, fake immutable Spotify reports. No player commands or preferences setters.
@interface SPTPlayerTrack ()
@property (nonatomic, strong) id URI;
@property (nonatomic, copy) NSString *UID;
@property (nonatomic, copy) NSDictionary *metadata;
@end
@implementation SPTPlayerTrack
@end
@interface SPTPlayerOptions ()
@property (nonatomic) BOOL repeatingTrack;
@end
@implementation SPTPlayerOptions
@end
@interface SPTPlayerState ()
@property (nonatomic, strong) SPTPlayerTrack *track;
@property (nonatomic, strong) id contextURI;
@property (nonatomic, strong) SPTPlayerOptions *options;
@property (nonatomic, copy) NSArray *future;
@end
@implementation SPTPlayerState
@end

static SPTPlayerState *state;
static SGTransitionSettings settings;
static BOOL local = YES, settingsKnown = YES;
static id<SGPlayerStateObserver> observer;
NSNotificationName const SGPlayerPlaybackLocationDidChangeNotification = @"local";
BOOL SGPlayerPlaybackIsLocal(void) { return local; }
BOOL SGTransitionSettingsRead(SGTransitionSettings *out) { *out = settings; return settingsKnown; }
SPTPlayerState *SGPlayerState(void) { return state; }
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> value) { observer = value; }
NSString *SGURIString(id value) {
    return [value isKindOfClass:NSString.class] ? value :
        [value isKindOfClass:NSURL.class] ? [value absoluteString] : nil;
}

static void require(BOOL ok, NSString *message) {
    if (!ok) { NSLog(@"FAIL: %@", message); exit(1); }
}
static SPTPlayerTrack *track(NSString *URI, NSString *UID, NSDictionary *metadata) {
    SPTPlayerTrack *t = [SPTPlayerTrack new];
    t.URI = URI; t.UID = UID; t.metadata = metadata;
    return t;
}
static void report(void) { [observer playerStateDidReport:state]; }
static void fixture(void) {
    state = [SPTPlayerState new];
    state.track = track(@"spotify:track:a", @"a1", @{@"duration": @"200000"});
    state.future = @[track(@"spotify:track:b", @"b1", @{@"duration": @"180000"})];
    state.contextURI = @"spotify:playlist:test";
    state.options = [SPTPlayerOptions new];
    settings = (SGTransitionSettings){NO, YES, 5000};
    local = settingsKnown = YES;
    report();
}
int main(void) {
    @autoreleasepool {
        __block NSUInteger changes = 0;
        [NSNotificationCenter.defaultCenter addObserverForName:SGAutoMixTransitionDidChangeNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) {
                require(NSThread.isMainThread, @"notification on main");
                changes++;
            }];
        SGAutoMixStartTransitionObserver();
        fixture();
        SGTransitionFacts *facts = SGAutoMixCurrentTransition();
        require(facts.kind == SGTransitionKindCrossfade && facts.timesKnown &&
                facts.outStart == 195 && facts.outEnd == 200 && facts.inStart == 0 && facts.inEnd == 5,
                @"5000 milliseconds crossfade -> literal seconds");
        NSUInteger before = changes;
        report();
        require(SGAutoMixCurrentTransition() == facts && changes == before,
                @"identical report preserves cached object without notification");
        state.track.metadata = @{@"duration": @"200000", @"position": @"198000", @"image_url": @"changed"};
        report();
        require(SGAutoMixCurrentTransition() == facts && changes == before,
                @"seek across window and unrelated metadata are not facts changes");
        ((SPTPlayerTrack *)state.future[0]).UID = @"b2";
        report();
        require([SGAutoMixCurrentTransition().toUID isEqual:@"b2"] && changes == before + 1,
                @"queue UID change notifies once");
        local = NO;
        report();
        require(SGAutoMixCurrentTransition() == nil && changes == before + 2,
                @"remote device must not advertise local blending");
        report();
        require(changes == before + 2, @"repeated absence does not notify");
        fixture();
        state.future = @[];
        report();
        require(!SGAutoMixCurrentTransition(), @"last song has no transition");
        fixture();
        state.contextURI = @"spotify:album:test";
        report();
        require(!SGAutoMixCurrentTransition(), @"ordered album gapless despite crossfade setting");
        fixture();
        settings = (SGTransitionSettings){NO, NO, 5000};
        report();
        require(!SGAutoMixCurrentTransition(), @"both styles off");
        fixture();
        settingsKnown = NO;
        report();
        require(!SGAutoMixCurrentTransition(), @"unloaded preferences are unknown");
        fixture();
        settings.automix = YES;
        report();
        require(SGAutoMixCurrentTransition().kind == SGTransitionKindCrossfade,
                @"no Automix metadata falls back to configured Crossfade");
        state.track.metadata = @{@"duration": @"188357",
            @"automix.fade_out_cuepoint.position": @"159403", @"automix.fade_out_cuepoint.tempo": @"140"};
        ((SPTPlayerTrack *)state.future[0]).metadata = @{@"duration": @"232500",
            @"automix.fade_in_cuepoint.position": @"0", @"automix.fade_in_cuepoint.tempo": @"142"};
        report();
        require(!SGAutoMixCurrentTransition(), @"Automix cue/tempo without mode must not invent Crossfade");
        state.track.metadata = @{@"duration": @"188357", @"automix.mode": @"default",
            @"automix.fade_out_cuepoint.position": @"159403", @"automix.fade_out_cuepoint.tempo": @"140"};
        ((SPTPlayerTrack *)state.future[0]).metadata = @{@"duration": @"232500", @"automix.mode": @"default",
            @"automix.fade_in_cuepoint.position": @"0", @"automix.fade_in_cuepoint.tempo": @"142"};
        report();
        facts = SGAutoMixCurrentTransition();
        require(facts.kind == SGTransitionKindSpotifyAutomix && !facts.timesKnown &&
                facts.outStart == 0 && facts.outEnd == 0 && facts.inStart == 0 && facts.inEnd == 0,
                @"real cue points alone do not expose fade windows (159.403 s is not the boundary)");
        ((SPTPlayerTrack *)state.future[0]).metadata = @{@"duration": @"232500", @"automix.mode": @"default",
            @"automix.fade_in_cuepoint.position": @"NaN", @"automix.fade_in_cuepoint.tempo": @"142"};
        report();
        require(!SGAutoMixCurrentTransition(), @"malformed pair metadata fails closed, not Crossfade");
        fixture();
        ((SPTPlayerTrack *)state.future[0]).URI = @"spotify:track:a";
        report();
        require([SGAutoMixCurrentTransition().fromUID isEqual:@"a1"] &&
                [SGAutoMixCurrentTransition().toUID isEqual:@"b1"],
                @"repeated URI with a different queue UID remains a pair");
        fixture();
        state.track.metadata = @{@"duration": @"3000"};
        ((SPTPlayerTrack *)state.future[0]).metadata = @{@"duration": @"2000"};
        report();
        facts = SGAutoMixCurrentTransition();
        require(facts.timesKnown && facts.outStart == 0 && facts.outEnd == 3 && facts.inEnd == 2,
                @"clamp each crossfade window to its own song");
        fixture();
        ((SPTPlayerTrack *)state.future[0]).metadata = @{};
        report();
        require(!SGAutoMixCurrentTransition().timesKnown, @"missing duration never invents times");
        state.track.metadata = @{@"duration": @"-1000"};
        report();
        require(!SGAutoMixCurrentTransition().timesKnown, @"inverted duration cannot form a window");
        fixture();
        state.options.repeatingTrack = YES;
        report();
        require(!SGAutoMixCurrentTransition(), @"repeating current does not blend to future");
        NSLog(@"PASS: AutoMix transition facts");
    }
    return 0;
}
