// The presets: built-in ones over a reset, and the user's own as a copy of every dsp key. Everything goes back
// in through AudioEffects.h's setters, so it is clamped and applied the way the page's own changes are.
#import "Core/SGLocalize.h"
#import "AudioEffects.h"
#import "AudioEffectsApply.h"
#import "AudioEffectsPresets.h"

static NSString *const kPrefix = @"spotifyglass.dsp.";

static NSUserDefaults *store(void) {
    return NSUserDefaults.standardUserDefaults;
}

// A value back through its setter: a switch (the key naming its own effect), a number, the gains as a
// list, or text. Anything else is left out, a preset from a later build naming a key this one lacks too.
static void setValue(NSString *key, id value) {
    if (![key hasPrefix:kPrefix]) return;
    if ([value isKindOfClass:NSArray.class]) SGDSPSetGains(key, value);
    else if ([value isKindOfClass:NSString.class]) SGDSPSetString(key, value);
    else if (![value isKindOfClass:NSNumber.class]) return;
    else if ([SGDSPEffectOf(key) isEqualToString:key]) SGDSPSetSwitch(key, [value boolValue]);
    else SGDSPSetNumber(key, [value doubleValue]);
}

// A pick is meant to be heard: the master switch, off until asked for, comes on with it.
static void turnOn(void) {
    if (!SGDSPSwitch(SGKeyDSP)) SGDSPSetSwitch(SGKeyDSP, YES);
}

static NSDictionary<NSString *, id> *currentValues(void) {
    NSDictionary<NSString *, id> *all = store().dictionaryRepresentation;
    NSMutableDictionary<NSString *, id> *values = [NSMutableDictionary dictionary];
    for (NSString *key in all) {
        if ([key hasPrefix:kPrefix]) values[key] = all[key];
    }
    return values;
}

#pragma mark - built in

// Each built-in preset's name and what it does, in the order builtInValues reads them. Shown only, so they
// are read in the person's language; a pick goes by its index.
static NSArray<NSArray<NSString *> *> *builtIn(void) {
    return @[
        @[SGL(@"settings.audioeffects.preset.bass_boost", @"Bass boost"), SGL(@"settings.audioeffects.preset.bass_boost.subtitle", @"Bass boost at 8 dB")],
        @[SGL(@"settings.audioeffects.preset.vocal_clarity", @"Vocal clarity"), SGL(@"settings.audioeffects.preset.vocal_clarity.subtitle", @"Equalizer on voices, a light compander")],
        @[SGL(@"settings.audioeffects.preset.late_night", @"Late night"), SGL(@"settings.audioeffects.preset.late_night.subtitle", @"Quiet and loud evened out, less bass")],
        @[SGL(@"settings.audioeffects.preset.concert_hall", @"Concert hall"), SGL(@"settings.audioeffects.preset.concert_hall.subtitle", @"A large hall's reverb, a wider stage")],
        @[SGL(@"settings.audioeffects.preset.warm_analog", @"Warm analog"), SGL(@"settings.audioeffects.preset.warm_analog.subtitle", @"Tube warmth, a warm equalizer")],
        @[SGL(@"settings.audioeffects.preset.headphone_comfort", @"Headphone comfort"), SGL(@"settings.audioeffects.preset.headphone_comfort.subtitle", @"Crossfeed, a softer top")],
        @[SGL(@"settings.audioeffects.preset.wide_stereo", @"Wide stereo"), SGL(@"settings.audioeffects.preset.wide_stereo.subtitle", @"Stereo widening")],
    ];
}

// The equalizer presets by their place in SGDSPEqualizerPresetNames, whose names are translated.
enum { kEqualizerVocal = 4, kEqualizerWarm = 5 };

static NSArray<NSNumber *> *equalizer(NSInteger preset) {
    return SGDSPEqualizerPreset(preset);
}

static NSDictionary<NSString *, id> *builtInValues(NSInteger index) {
    switch (index) {
        case 0: return @{SGKeyDSPBass: @YES, SGKeyDSPBassGain: @8};
        case 1: return @{SGKeyDSPEqualizer: @YES, SGKeyDSPEqualizerGains: equalizer(kEqualizerVocal),
                         SGKeyDSPCompander: @YES, SGKeyDSPCompanderGains: @[@0, @0.2, @0.3, @0.3, @0.3, @0.2, @0]};
        // The compander over 0 lifts the quiet parts and holds the loud ones; the gain brings the level back.
        case 2: return @{SGKeyDSPCompander: @YES, SGKeyDSPCompanderGains: @[@0.6, @0.7, @0.8, @0.8, @0.8, @0.7, @0.6],
                         SGKeyDSPCompanderTime: @0.3, SGKeyDSPEqualizer: @YES,
                         SGKeyDSPEqualizerGains: @[@-6, @-5, @-4, @-2, @-1, @0, @0, @0, @0, @0, @0, @0, @-1, @-2, @-2],
                         SGKeyDSPPostGain: @3, SGKeyDSPLimiterThreshold: @-3};
        case 3: return @{SGKeyDSPReverb: @YES, SGKeyDSPReverbPreset: @7, SGKeyDSPReverbAmount: @40,
                         SGKeyDSPStereoWide: @YES, SGKeyDSPStereoWideLevel: @65};
        case 4: return @{SGKeyDSPTube: @YES, SGKeyDSPTubeDrive: @6, SGKeyDSPEqualizer: @YES, SGKeyDSPEqualizerGains: equalizer(kEqualizerWarm)};
        case 5: return @{SGKeyDSPCrossfeed: @YES, SGKeyDSPCrossfeedMode: @2, SGKeyDSPEqualizer: @YES,
                         SGKeyDSPEqualizerGains: @[@0, @0, @0, @0, @0, @0, @0, @0, @0, @0, @-1, @-2, @-2, @-3, @-3]};
        case 6: return @{SGKeyDSPStereoWide: @YES, SGKeyDSPStereoWideLevel: @75};
    }
    return nil;
}

NSArray<NSString *> *SGDSPBuiltInPresetNames(void) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSArray<NSString *> *preset in builtIn()) [names addObject:preset[0]];
    return names;
}

NSString *SGDSPBuiltInPresetDetail(NSInteger index) {
    NSArray<NSArray<NSString *> *> *all = builtIn();
    return index >= 0 && index < (NSInteger)all.count ? all[(NSUInteger)index][1] : nil;
}

void SGDSPLoadBuiltInPreset(NSInteger index) {
    NSDictionary<NSString *, id> *values = builtInValues(index);
    if (!values) return;
    NSMutableDictionary<NSString *, id> *kept = [NSMutableDictionary dictionary];
    NSDictionary<NSString *, id> *now = currentValues();
    for (NSString *key in now) {
        if ([SGDSPEffectOf(key) isEqualToString:SGKeyDSPGraphicEq]) kept[key] = now[key];
    }
    SGDSPResetAll();
    for (NSString *key in kept) setValue(key, kept[key]);
    for (NSString *key in values) setValue(key, values[key]);
    turnOn();
}

#pragma mark - the user's

static NSDictionary<NSString *, NSDictionary *> *userPresets(void) {
    id presets = [store() objectForKey:SGKeyDSPUserPresets];
    return [presets isKindOfClass:NSDictionary.class] ? presets : @{};
}

NSArray<NSString *> *SGDSPUserPresetNames(void) {
    return [userPresets().allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

void SGDSPSaveUserPreset(NSString *name) {
    if (!name.length) return;
    NSMutableDictionary *presets = [userPresets() mutableCopy];
    presets[name] = currentValues();
    [store() setObject:presets forKey:SGKeyDSPUserPresets];
}

BOOL SGDSPLoadUserPreset(NSString *name) {
    NSDictionary *values = userPresets()[name];
    if (![values isKindOfClass:NSDictionary.class]) return NO;
    SGDSPResetAll();
    for (NSString *key in values) setValue(key, values[key]);
    turnOn();
    return YES;
}

void SGDSPDeleteUserPreset(NSString *name) {
    NSMutableDictionary *presets = [userPresets() mutableCopy];
    [presets removeObjectForKey:name];
    [store() setObject:presets forKey:SGKeyDSPUserPresets];
}

#pragma mark - GraphicEQ text

// One line: AutoEq's files end in a newline, and a copy out of a web page often has more.
NSString *SGDSPGraphicEqLine(NSString *text) {
    NSArray<NSString *> *words = [text ?: @"" componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    words = [words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    NSString *line = [words componentsJoinedByString:@" "];
    return [line.lowercaseString hasPrefix:@"graphiceq:"] ? line : nil;
}
