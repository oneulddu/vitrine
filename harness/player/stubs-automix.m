// What the automix scenario stands in for: AutoMix's facts (Shared/AutoMix/SGTransitionFacts.m, whose own harness is
// harness/automix), Spotify's three playback settings behind AutoMix.x, and PlayerState.x's upcoming tracks. The
// facts are made by the scenario and posted the way the real cache posts them, on main, only when they change.
#import <UIKit/UIKit.h>
#import "Shared/AutoMix/AutoMix.h"
#import "Shared/Player/PlayerState.h"
#import "Core/SGPrefs.h"

@implementation SGTransitionFacts
+ (instancetype)sgr_harnessFrom:(NSString *)fromURI to:(NSString *)toURI kind:(SGTransitionKind)kind known:(BOOL)known
                       outStart:(double)outStart outEnd:(double)outEnd inStart:(double)inStart inEnd:(double)inEnd {
    SGTransitionFacts *facts = [super new];
    facts->_fromURI = [fromURI copy];
    facts->_toURI = [toURI copy];
    facts->_kind = kind;
    facts->_timesKnown = known;
    facts->_outStart = outStart;
    facts->_outEnd = outEnd;
    facts->_inStart = inStart;
    facts->_inEnd = inEnd;
    return facts;
}
@end

NSNotificationName const SGAutoMixTransitionDidChangeNotification = @"SGAutoMixTransitionDidChangeNotification";
static SGTransitionFacts *sg_harnessFacts;
SGTransitionFacts *SGAutoMixCurrentTransition(void) { return sg_harnessFacts; }
void SGRHarnessSetTransition(SGTransitionFacts *facts) {
    if (facts == sg_harnessFacts) return;
    sg_harnessFacts = facts;
    [NSNotificationCenter.defaultCenter postNotificationName:SGAutoMixTransitionDidChangeNotification object:nil];
}

// Spotify's settings as its Playback page would leave them, posted the way AutoMix.x's setter hooks post them, on main
// after the write; the page's writes are counted.
NSNotificationName const SGTransitionSettingsDidChangeNotification = @"SGTransitionSettingsDidChangeNotification";
static SGTransitionSettings sg_settings = {NO, YES, 5000};
static NSUInteger sg_settingWrites;
NSUInteger SGRHarnessSettingWrites(void) { return sg_settingWrites; }
void SGRHarnessSetSpotifySettings(SGTransitionSettings settings) {
    sg_settings = settings;
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:SGTransitionSettingsDidChangeNotification object:nil];
    });
}
BOOL SGTransitionSettingsRead(SGTransitionSettings *settings) {
    *settings = sg_settings;
    return YES;
}
void SGAutoMixApply(BOOL on) { sg_settingWrites++; }
SGAutoMixStyle SGAutoMixCurrentStyle(void) {
    if (SGFlag(SGKeyAutoMix, NO)) return sg_settings.automix ? SGAutoMixBeatMatched : SGAutoMixCrossfade;
    return SGInt(SGKeyAutoMixStyle, SGAutoMixBeatMatched);
}
void SGAutoMixSetStyle(SGAutoMixStyle style) { sg_settingWrites++; }
void SGAutoMixSetSeconds(NSInteger seconds) { sg_settingWrites++; }
BOOL SGAutoMixAccountAllows(void) { return YES; }

NSArray<SPTPlayerTrack *> *SGPlayerUpcomingTracks(SPTPlayerState *state, NSUInteger limit) {
    NSMutableArray<SPTPlayerTrack *> *tracks = [NSMutableArray array];
    for (id item in state.future) {
        if (tracks.count == limit) break;
        if ([item isKindOfClass:SPTPlayerTrack.class]) [tracks addObject:item];
    }
    return tracks;
}
