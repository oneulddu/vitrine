// Checks preset files (AudioEffectsPresets.m) on the Mac through the real settings: a preset written and read
// back, and the files the reader refuses or trims.
//
//     ./build.sh presets && build/preset-files-check
//
// Every line prints ok or FAIL; the exit status is the number of failures.
#import <Foundation/Foundation.h>
#import "AudioEffects.h"
#import "AudioEffectsApply.h"
#import "AudioEffectsPresets.h"

static int failures;

static void check(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "ok  " : "FAIL", what.UTF8String);
    failures += !ok;
}

// The engine is not here.
void SGDSPApply(NSString *effect) {
}

static void clearDefaults(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    for (NSString *key in store.dictionaryRepresentation) {
        if ([key hasPrefix:@"spotifyglass."]) [store removeObjectForKey:key];
    }
}

static NSData *json(id object) {
    return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
}

static NSDictionary *readFile(NSData *data, NSString **name, NSString **error) {
    return SGDSPReadPresetFile(data, @"From file", name, error);
}

int main(void) {
    @autoreleasepool {
        clearDefaults();

        // A preset of the user's, written and read back.
        SGDSPSetSwitch(SGKeyDSPBass, YES);
        SGDSPSetNumber(SGKeyDSPBassGain, 9);
        SGDSPSetGains(SGKeyDSPEqualizerGains, @[@1, @2, @3]);
        SGDSPSetString(SGKeyDSPConvolverFile, @"Hall.wav");
        SGDSPSetSwitch(SGKeyDSP, YES);
        SGDSPSaveUserPreset(@"Late/night: mine");
        NSString *fileName = nil;
        NSData *data = SGDSPPresetFileData(@"Late/night: mine", &fileName);
        check(data != nil, @"a saved preset becomes a file");
        check([fileName isEqualToString:@"Late-night- mine.vitrine-preset.json"], [NSString stringWithFormat:@"its file name is safe for Files (%@)", fileName]);
        NSDictionary *file = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        check([file[@"format"] isEqual:@"vitrine.audio-preset"] && [file[@"version"] isEqual:@1], @"the file says what it is");
        check(file[@"values"][SGKeyDSP] == nil, @"the master switch stays out of the file");
        NSString *name = nil, *error = nil;
        NSDictionary *values = readFile(data, &name, &error);
        check([name isEqualToString:@"Late/night: mine"], @"the name comes back as it was");
        check([values[SGKeyDSPBass] boolValue] && [values[SGKeyDSPBassGain] doubleValue] == 9, @"switches and numbers come back");
        check([values[SGKeyDSPConvolverFile] isEqualToString:@"Hall.wav"], @"a file name comes back");
        check([SGDSPPresetMissingFiles(values) containsObject:@"Hall.wav"], @"the impulse response it names is missing here");
        check(SGDSPPresetFileData(@"Nobody", NULL) == nil, @"no file for a preset that is not there");

        // Saved under a free name, then loaded.
        SGDSPResetAll();
        check([SGDSPUniquePresetName(@"Late/night: mine") isEqualToString:@"Late/night: mine 2"], @"a taken name gets a number");
        SGDSPSaveUserPresetValues(@"Imported", values);
        check(SGDSPUserPresetExists(@"Imported") && SGDSPLoadUserPreset(@"Imported"), @"an imported preset is saved and loads");
        check(SGDSPSwitch(SGKeyDSPBass) && SGDSPNumber(SGKeyDSPBassGain) == 9, @"loading it sets the effects");

        // What the reader refuses.
        check(!readFile(nil, NULL, &error) && error.length, @"no data is refused");
        check(!readFile([@"[1,2]" dataUsingEncoding:NSUTF8StringEncoding], NULL, &error) && error.length, @"an array is refused");
        check(!readFile(json(@{@"format": @"other", @"version": @1, @"values": @{SGKeyDSPBass: @YES}}), NULL, &error), @"another format is refused");
        check(!readFile(json(@{@"format": @"vitrine.audio-preset", @"version": @2, @"values": @{SGKeyDSPBass: @YES}}), NULL, &error)
              && [error containsString:@"newer"], [NSString stringWithFormat:@"a later version says to update (%@)", error]);
        check(!readFile(json(@{@"format": @"vitrine.audio-preset", @"version": @YES, @"values": @{SGKeyDSPBass: @YES}}), NULL, &error), @"a boolean version is refused");
        check(!readFile(json(@{@"format": @"vitrine.audio-preset", @"version": @1.5, @"values": @{SGKeyDSPBass: @YES}}), NULL, &error), @"a fractional version is refused");
        check(!readFile(json(@{@"format": @"vitrine.audio-preset", @"version": @1, @"values": @[]}), NULL, &error), @"values that are not a dictionary are refused");
        check(!readFile(json(@{@"format": @"vitrine.audio-preset", @"version": @1, @"values": @{@"spotifyglass.font": @3, SGKeyDSP: @YES}}), NULL, &error), @"nothing usable is refused");
        NSMutableData *big = [NSMutableData dataWithLength:256 * 1024 + 1];
        check(!readFile(big, NULL, &error) && [error containsString:@"large"], @"over 256 KB is refused");

        // What it trims.
        NSDictionary *trimmed = readFile(json(@{@"format": @"vitrine.audio-preset", @"version": @1, @"name": @"  ",
            @"values": @{SGKeyDSPBass: @YES, SGKeyDSP: @YES, @"spotifyglass.font": @3, SGKeyDSPBassGain: @"loud",
                         SGKeyDSPConvolverFile: @"../../etc/passwd", SGKeyDSPDDCFile: @".hidden.vdc", SGKeyDSPLiveprogFile: @"ok.eel"}}), &name, &error);
        check(trimmed[SGKeyDSPBass] && !trimmed[SGKeyDSP] && !trimmed[@"spotifyglass.font"], @"only this build's keys are kept, never the master switch");
        check(!trimmed[SGKeyDSPBassGain], @"a value of the wrong type is dropped");
        check(!trimmed[SGKeyDSPConvolverFile] && !trimmed[SGKeyDSPDDCFile] && [trimmed[SGKeyDSPLiveprogFile] isEqual:@"ok.eel"], @"a file name with a path or a dot first is dropped");
        check([name isEqualToString:@"From file"], @"a blank name takes the file's");
        NSString *longName = [@"" stringByPaddingToLength:120 withString:@"가" startingAtIndex:0];
        readFile(json(@{@"format": @"vitrine.audio-preset", @"version": @1, @"name": longName, @"values": @{SGKeyDSPBass: @YES}}), &name, NULL);
        check(name.length == 80, @"a long name is cut to 80 characters");

        clearDefaults();
        printf("%d failure(s)\n", failures);
        return failures;
    }
}
