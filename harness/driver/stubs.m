// The tweak's speed, pitch, Sing and landscape commands, which the phone has and the mock app does not: the
// driver's commands still exist and succeed, they just have nothing to act on here. The lossless and AutoMix
// probes reach Spotify's own settings, so they report the harness has none rather than pretend.
#import <UIKit/UIKit.h>
#import "Diagnostics/Diagnostics.h"

double SGPlayerSpeed(void) { return 1; }
void SGSetPlayerSpeed(double speed) {}

void SGSetSingOn(BOOL on) {}

void SGRPlayerShowLandscape(BOOL show) {}

NSDictionary *SGLosslessProbe(NSString *verb, NSDictionary *p, NSString **error) {
    if (error) *error = @"lossless is not in the driver harness";
    return nil;
}

NSDictionary *SGAutoMixProbeCommand(NSDictionary *p, NSString **error) {
    if (error) *error = @"AutoMix is not in the driver harness";
    return nil;
}
