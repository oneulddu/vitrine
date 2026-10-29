// The tweak's speed, pitch, Sing and landscape commands, which the phone has and the mock app does not: the
// driver's commands still exist and succeed, they just have nothing to act on here. The lossless and AutoMix
// probes reach Spotify's own settings, so they report the harness has none rather than pretend.
#import <UIKit/UIKit.h>
#import "Diagnostics/Diagnostics.h"
#import "Shared/Fonts/Fonts.h"
#import "Shared/Fonts/FontLibrary.h"

// The production PiP renderer resolves fonts through the existing app facilities. This mock
// has system fonts, but no imported files, downloaded library or localization bundle.
NSString *SGL(NSString *key, NSString *english) { return english; }
SGAppFont SGAppFontChosen(void) { return SGAppFontSystem; }
NSArray<NSString *> *SGAppFontFamilies(void) { return @[]; }
NSString *SGRegisterCustomFont(void) { return nil; }
NSArray<SGLibraryFont *> *SGFontLibrary(void) { return @[]; }
BOOL SGFontLibraryInstalled(NSString *identifier) { return NO; }
NSString *SGRegisteredCustomFont(void) { return nil; }
void SGRegisterCustomFontAsync(void) {}
NSString *SGFontLibraryRegisteredFamily(NSString *identifier) { return nil; }
void SGFontLibraryRegisterAsync(NSString *identifier, void (^done)(NSString *family)) {}
SGLibraryFont *SGFontLibraryFont(NSString *identifier) { return nil; }

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
