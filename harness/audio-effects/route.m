// Checks the corrections remembered per output (AutoEq.m) on the Mac, through the real settings: what a route
// change to each kind of output does to the Graphic EQ, with AVAudioSession's part played by direct calls.
//
//     ./build.sh route && build/route-check
//
// Every line prints ok or FAIL; the exit status is the number of failures. The settings live in the check's
// own defaults domain, cleared before and after.
#import <Foundation/Foundation.h>
#import "AudioEffects.h"
#import "AudioEffectsApply.h"
#import "AudioEffectsPresets.h"

static int failures;

static void check(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "ok  " : "FAIL", what.UTF8String);
    failures += !ok;
}

// The engine is not here; what it is handed is counted by whether the output baseline was stored by then.
// A process told to die at the Nth apply made with a baseline stored dies there, as a kill half-way through
// handing a preset to the engine would: what is stored by then stays.
static BOOL countApplies;
static int appliesWithBaseline, appliesWithoutBaseline;
static int dieAtApply, appliesToDeath;
void SGDSPApply(NSString *effect) {
    if (!countApplies) return;
    if ([NSUserDefaults.standardUserDefaults objectForKey:SGKeyDSPOutputBaseline]) appliesWithBaseline++;
    else appliesWithoutBaseline++;
    if (dieAtApply && appliesWithBaseline && ++appliesToDeath == dieAtApply) {
        [NSUserDefaults.standardUserDefaults synchronize];
        fflush(stdout);
        _exit(failures);
    }
}

static void clearDefaults(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    for (NSString *key in store.dictionaryRepresentation) {
        if ([key hasPrefix:@"spotifyglass."]) [store removeObjectForKey:key];
    }
}

static NSString *const kAirPods = @"AA-BB-tacl", *const kSony = @"CC-DD-tacl", *const kSpeaker = @"Speaker";
static NSString *const kLine = @"GraphicEQ: 20 -1.0; 1000 0.0; 20000 2.0";
static NSString *const kSonyLine = @"GraphicEQ: 20 3.0; 1000 0.0; 20000 -2.0";

// What the Graphic EQ plays: the headphone's folder, or "" for nothing; "off" when its switch is off.
static NSString *playing(void) {
    if (!SGDSPSwitch(SGKeyDSPGraphicEq)) return @"off";
    return SGDSPString(SGKeyDSPGraphicEqHeadphone);
}

static NSString *const kPlain = @"PLAIN-speaker", *const kMappedA = @"MAP-A-tacl", *const kMappedB = @"MAP-B-tacl";

// A route change to the output with the applies counted: how many came before and after the baseline existed.
static void route(NSString *uid, NSString *name) {
    appliesWithBaseline = appliesWithoutBaseline = 0;
    countApplies = YES;
    SGAutoEqOutputChanged(uid, name);
    countApplies = NO;
}

static NSDictionary *baseline(void) {
    return [NSUserDefaults.standardUserDefaults objectForKey:SGKeyDSPOutputBaseline];
}

// The user's own taste before any mapped output: the tube at 4 dB, a post gain of 1, the effects on.
static void userValues(void) {
    SGDSPResetAll();
    SGDSPSetSwitch(SGKeyDSPTube, YES);
    SGDSPSetNumber(SGKeyDSPTubeDrive, 4);
    SGDSPSetNumber(SGKeyDSPPostGain, 1);
    SGDSPSetSwitch(SGKeyDSP, YES);
}

static BOOL userValuesBack(void) {
    return SGDSPSwitch(SGKeyDSPTube) && SGDSPNumber(SGKeyDSPTubeDrive) == 4 && SGDSPNumber(SGKeyDSPPostGain) == 1 && !SGDSPSwitch(SGKeyDSPBass);
}

static BOOL nightApplied(void) {
    return SGDSPSwitch(SGKeyDSPBass) && SGDSPNumber(SGKeyDSPBassGain) == 6 && SGDSPNumber(SGKeyDSPPostGain) == -2 && !SGDSPSwitch(SGKeyDSPTube);
}

static void savePresets(void) {
    SGDSPSaveUserPresetValues(@"Night", @{SGKeyDSPBass: @YES, SGKeyDSPBassGain: @6, SGKeyDSPPostGain: @-2});
    SGDSPSaveUserPresetValues(@"Wide", @{SGKeyDSPStereoWide: @YES, SGKeyDSPStereoWideLevel: @80});
}

// A launch killed while audio played through a mapped output, in two processes: the first enters it and exits
// with the baseline stored; the second starts with only what was stored and is told the speaker.
static int killedOnMapped(BOOL first) {
    if (first) {
        clearDefaults();
        savePresets();
        userValues();
        SGAutoEqOutputChanged(kMappedA, @"Mapped A");
        SGAutoEqSetOutputPreset(@"Night");
        check(nightApplied() && baseline(), @"first launch: the preset is on and the baseline stored");
        [NSUserDefaults.standardUserDefaults synchronize];
        return failures;
    }
    check(nightApplied() && baseline(), @"relaunch: what the killed launch left is there");
    SGAutoEqOutputChanged(kPlain, @"Speaker");
    check(userValuesBack() && !baseline(), @"relaunch on an output without a preset: the user's values are back, the baseline gone");
    check(SGDSPSwitch(SGKeyDSP), @"relaunch: the master switch is as it was");
    clearDefaults();
    [NSUserDefaults.standardUserDefaults synchronize];
    return failures;
}

// The user edits on a mapped output, the launch is killed, and the next one starts on the same output: the edits
// and the baseline stay, nothing is applied; leaving then keeps the edits, which differ from the digest.
static int editedOnMapped(BOOL first) {
    if (first) {
        clearDefaults();
        savePresets();
        userValues();
        SGAutoEqOutputChanged(kMappedA, @"Mapped A");
        SGAutoEqSetOutputPreset(@"Night");
        SGDSPSetNumber(SGKeyDSPPostGain, 5);
        check(SGDSPNumber(SGKeyDSPPostGain) == 5 && baseline(), @"first launch: an edit made on the mapped output");
        [NSUserDefaults.standardUserDefaults synchronize];
        return failures;
    }
    NSDictionary *stored = baseline();
    check(stored != nil, @"relaunch on the same output: the baseline is stored");
    route(kMappedA, @"Mapped A");
    check(SGDSPNumber(SGKeyDSPPostGain) == 5 && SGDSPSwitch(SGKeyDSPBass) && SGDSPNumber(SGKeyDSPBassGain) == 6,
          @"relaunch on the same output: the edit is kept, the preset not applied over it");
    check(appliesWithBaseline + appliesWithoutBaseline == 0, @"relaunch on the same output: nothing handed to the engine");
    check([baseline() isEqualToDictionary:stored], @"relaunch on the same output: the baseline and its digest are kept");
    route(kPlain, @"Speaker");
    check(SGDSPNumber(SGKeyDSPPostGain) == 5 && SGDSPSwitch(SGKeyDSPBass) && !SGDSPSwitch(SGKeyDSPTube),
          @"leaving after the relaunch: the edited values are kept, since they differ from the digest");
    check(!baseline(), @"leaving after the relaunch: the baseline is dropped");
    clearDefaults();
    [NSUserDefaults.standardUserDefaults synchronize];
    return failures;
}

// A launch killed half-way through the move from mapped output A to mapped output B (the baseline written for B,
// the settings part-way to B's preset), then started again, in two processes each. `after`: 0 on the speaker,
// 1 on B again.
static NSString *const kHalfWay = @"half-way through the move to B";
static int killedBetweenMapped(BOOL first, int after) {
    if (first) {
        clearDefaults();
        savePresets();
        userValues();
        SGAutoEqOutputChanged(kMappedA, @"Mapped A");
        SGAutoEqSetOutputPreset(@"Night");
        SGAutoEqOutputChanged(kMappedB, @"Mapped B");
        SGAutoEqSetOutputPreset(@"Wide");
        SGAutoEqOutputChanged(kMappedA, @"Mapped A");
        check(nightApplied(), @"first launch: A's preset is on");
        dieAtApply = 13;   // after the reset's 12 and one of B's two values
        route(kMappedB, @"Mapped B");
        check(NO, @"the launch was not killed half-way");
        return failures;
    }
    check(baseline()[@"pending"] != nil, @"relaunch: the baseline says the apply was cut short");
    if (after == 0) {
        route(kPlain, @"Speaker");
        check(userValuesBack() && !baseline(), @"killed half-way A to B, relaunch on the speaker: the original values are back");
        check(SGDSPSwitch(SGKeyDSP), @"killed half-way, relaunch on the speaker: the master switch is as it was");
    } else {
        route(kMappedB, @"Mapped B");
        check(SGDSPSwitch(SGKeyDSPStereoWide) && SGDSPNumber(SGKeyDSPStereoWideLevel) == 80 && !SGDSPSwitch(SGKeyDSPBass),
              @"killed half-way A to B, relaunch on B: B's preset is applied whole");
        check(baseline() && !baseline()[@"pending"], @"killed half-way, relaunch on B: the apply is done, nothing pending");
        route(kPlain, @"Speaker");
        check(userValuesBack() && !baseline(), @"killed half-way, relaunch on B, then out: the original values are back");
    }
    clearDefaults();
    [NSUserDefaults.standardUserDefaults synchronize];
    return failures;
}

// A launch killed part-way through putting the user's values back on leaving a mapped output for the speaker,
// then started on the speaker.
static int killedWhileLeaving(BOOL first) {
    if (first) {
        clearDefaults();
        savePresets();
        userValues();
        SGAutoEqOutputChanged(kMappedA, @"Mapped A");
        SGAutoEqSetOutputPreset(@"Night");
        check(nightApplied(), @"first launch: the preset is on");
        dieAtApply = 13;   // after the reset's 12 and one of the user's values
        route(kPlain, @"Speaker");
        check(NO, @"the launch was not killed half-way through the restore");
        return failures;
    }
    check(baseline() != nil && !nightApplied() && !userValuesBack(), @"relaunch: a restore left half done, the baseline still there");
    route(kPlain, @"Speaker");
    check(userValuesBack() && !baseline(), @"killed half-way through the restore, relaunch on the speaker: the original values are back");
    check(SGDSPSwitch(SGKeyDSP), @"killed half-way through the restore: the master switch is as it was");
    clearDefaults();
    [NSUserDefaults.standardUserDefaults synchronize];
    return failures;
}

// Runs this tool again for one half of the relaunch check; its output is shown, its failures counted.
static void relaunchPhase(NSString *phase) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments[0]];
    task.arguments = @[phase];
    [task launchAndReturnError:nil];
    [task waitUntilExit];
    failures += task.terminationStatus;
    [NSUserDefaults.standardUserDefaults synchronize];
}

static void checkPresetPerOutput(void) {
    clearDefaults();
    savePresets();
    userValues();
    SGAutoEqOutputChanged(kPlain, @"Speaker");

    // A mapped output is made from the output playing: the preset is on at once, the baseline first.
    SGAutoEqOutputChanged(kMappedA, @"Mapped A");
    check(!baseline(), @"an output without a preset stores no baseline");
    SGAutoEqSetOutputPreset(@"Night");
    SGAutoEqOutputChanged(kPlain, @"Speaker");
    check(userValuesBack() && !baseline(), @"choosing the preset on the playing output applies it and leaving restores");

    // Enter: preset applied, baseline (the user's values and the applied digest) stored before anything is applied.
    route(kMappedA, @"Mapped A");
    check(nightApplied(), @"enter a mapped output: the preset is applied");
    check(appliesWithBaseline > 0 && appliesWithoutBaseline == 0, @"enter: the baseline was stored before the first apply");
    NSDictionary *saved = baseline();
    check([saved[@"values"][SGKeyDSPTube] boolValue] && [saved[@"values"][SGKeyDSPTubeDrive] doubleValue] == 4
          && [saved[@"applied"] isEqualToString:SGDSPValuesDigest(SGDSPCurrentValues())],
          @"enter: the baseline holds the user's values and the digest of what was applied");
    check(SGDSPSwitch(SGKeyDSP), @"enter: the master switch untouched");

    // Leave unchanged: the user's values back, the baseline removed only after the restore.
    route(kPlain, @"Speaker");
    check(userValuesBack(), @"leave unchanged: the baseline's values are back");
    check(appliesWithBaseline > 0 && appliesWithoutBaseline == 0 && !baseline(), @"leave unchanged: the baseline cleared after the restore, not before");
    check(SGDSPSwitch(SGKeyDSP), @"leave: the master switch untouched");

    // Leave after the user changed something: their values stay, the baseline goes.
    SGAutoEqOutputChanged(kMappedA, @"Mapped A");
    SGDSPSetNumber(SGKeyDSPPostGain, 5);
    SGAutoEqOutputChanged(kPlain, @"Speaker");
    check(SGDSPNumber(SGKeyDSPPostGain) == 5 && SGDSPSwitch(SGKeyDSPBass) && !SGDSPSwitch(SGKeyDSPTube), @"leave after a change: the user's values are kept");
    check(!baseline(), @"leave after a change: the baseline is dropped");

    // Mapped to mapped: the new preset, the first baseline.
    userValues();
    SGAutoEqOutputChanged(kMappedB, @"Mapped B");
    SGAutoEqSetOutputPreset(@"Wide");
    SGAutoEqOutputChanged(kPlain, @"Speaker");
    check(userValuesBack(), @"B set up");
    SGAutoEqOutputChanged(kMappedA, @"Mapped A");
    NSDictionary *first = baseline();
    SGAutoEqOutputChanged(kMappedB, @"Mapped B");
    check(SGDSPSwitch(SGKeyDSPStereoWide) && SGDSPNumber(SGKeyDSPStereoWideLevel) == 80 && !SGDSPSwitch(SGKeyDSPBass), @"mapped to mapped: the new preset is applied");
    check([baseline()[@"values"] isEqualToDictionary:first[@"values"]] && [baseline()[@"applied"] isEqualToString:SGDSPValuesDigest(SGDSPCurrentValues())],
          @"mapped to mapped: the first baseline kept, the digest the new preset's");
    SGAutoEqOutputChanged(kPlain, @"Speaker");
    check(userValuesBack() && !baseline(), @"mapped to mapped, then out: the original values are back");

    // A preset since deleted is None.
    SGDSPDeleteUserPreset(@"Night");
    SGAutoEqOutputChanged(kMappedA, @"Mapped A");
    check(userValuesBack() && !baseline(), @"a deleted preset: nothing applied, no baseline");
    SGAutoEqOutputChanged(kPlain, @"Speaker");

    // Deleting the preset the playing output uses settles it as leaving does; other outputs have None.
    savePresets();
    SGAutoEqOutputChanged(kMappedA, @"Mapped A");
    SGAutoEqSetOutputPreset(@"Night");
    check(nightApplied(), @"A plays Night");
    SGDSPDeleteUserPreset(@"Night");
    check(userValuesBack() && !baseline(), @"deleting the preset the playing output uses: the values are back, the baseline gone");
    check([SGAutoEqOutputPreset(kMappedA) isEqualToString:@""], @"deleting the preset: the output has None");
    savePresets();
    SGAutoEqSetOutputPreset(@"Night");
    SGDSPSetNumber(SGKeyDSPPostGain, 5);
    SGDSPDeleteUserPreset(@"Night");
    check(SGDSPNumber(SGKeyDSPPostGain) == 5 && SGDSPSwitch(SGKeyDSPBass) && !baseline(),
          @"deleting the preset after a change: the user's values are kept, the baseline gone");
    SGAutoEqOutputChanged(kPlain, @"Speaker");
    userValues();
    savePresets();
    SGAutoEqOutputChanged(kMappedB, @"Mapped B");
    SGAutoEqSetOutputPreset(@"Night");
    SGAutoEqOutputChanged(kPlain, @"Speaker");
    SGDSPDeleteUserPreset(@"Night");
    check([SGAutoEqOutputPreset(kMappedB) isEqualToString:@""], @"deleting the preset: another output that had it has None");
    savePresets();
    route(kMappedB, @"Mapped B");
    check(userValuesBack() && !baseline(), @"a preset made again under the deleted name is not B's");
    SGAutoEqOutputChanged(kPlain, @"Speaker");

    // A sparse preset and the user setting its defaults by hand are no change.
    SGDSPSaveUserPresetValues(@"Sparse", @{SGKeyDSPCrossfeed: @YES});
    SGAutoEqOutputChanged(kMappedA, @"Mapped A");
    SGAutoEqSetOutputPreset(@"Sparse");
    SGDSPSetNumber(SGKeyDSPCrossfeedMode, 2);
    SGDSPSetSwitch(SGKeyDSPTube, NO);
    SGDSPSetNumber(SGKeyDSPPostGain, 0);
    SGAutoEqOutputChanged(kPlain, @"Speaker");
    check(userValuesBack() && !baseline(), @"a default set by hand on a sparse preset's output: leaving restores the baseline");
    SGAutoEqOutputChanged(kMappedA, @"Mapped A");
    SGAutoEqSetOutputPreset(nil);
    SGAutoEqOutputChanged(kPlain, @"Speaker");

    // The master switch off stays off, and None picked on the playing output puts the values back.
    savePresets();
    SGDSPSetSwitch(SGKeyDSP, NO);
    SGAutoEqOutputChanged(kMappedA, @"Mapped A");
    SGAutoEqSetOutputPreset(@"Night");
    check(nightApplied() && !SGDSPSwitch(SGKeyDSP), @"effects off: the preset is applied and they stay off");
    SGAutoEqSetOutputPreset(nil);
    check(userValuesBack() && !baseline() && !SGDSPSwitch(SGKeyDSP), @"None chosen on the playing output: the values are back, the baseline gone");
    check([SGAutoEqOutputPreset(kMappedA) isEqualToString:@""], @"None is stored as no preset");
    SGAutoEqOutputChanged(kPlain, @"Speaker");

    // The output's remembered correction goes over the preset's Graphic EQ, and is still the output's own.
    SGAutoEqOutputChanged(kMappedA, @"Mapped A");
    SGAutoEqSetOutputPreset(@"Wide");
    SGAutoEqApplyText(@"crinacle/AirPods%20Pro", kLine);
    check([SGAutoEqRememberedOutputs().firstObject[@"preset"] isEqualToString:@"Wide"], @"a pick on the output keeps its preset");
    SGAutoEqOutputChanged(kPlain, @"Speaker");
    SGAutoEqOutputChanged(kMappedA, @"Mapped A");
    check(SGDSPSwitch(SGKeyDSPStereoWide) && [playing() isEqualToString:@"crinacle/AirPods%20Pro"], @"the preset with the output's correction over it");
    SGAutoEqOutputChanged(kPlain, @"Speaker");

    relaunchPhase(@"killed-on-mapped");
    relaunchPhase(@"relaunch");
    relaunchPhase(@"edited-on-mapped");
    relaunchPhase(@"relaunch-same");
    relaunchPhase(@"killed-between");
    relaunchPhase(@"after-killed-speaker");
    relaunchPhase(@"killed-between");
    relaunchPhase(@"after-killed-target");
    relaunchPhase(@"killed-leaving");
    relaunchPhase(@"after-killed-leaving");
}

int main(int argc, char **argv) {
    if (argc > 1 && !strcmp(argv[1], "killed-on-mapped")) return killedOnMapped(YES);
    if (argc > 1 && !strcmp(argv[1], "relaunch")) return killedOnMapped(NO);
    if (argc > 1 && !strcmp(argv[1], "edited-on-mapped")) return editedOnMapped(YES);
    if (argc > 1 && !strcmp(argv[1], "relaunch-same")) return editedOnMapped(NO);
    if (argc > 1 && !strcmp(argv[1], "killed-between")) return killedBetweenMapped(YES, 0);
    if (argc > 1 && !strcmp(argv[1], "after-killed-speaker")) return killedBetweenMapped(NO, 0);
    if (argc > 1 && !strcmp(argv[1], "killed-leaving")) return killedWhileLeaving(YES);
    if (argc > 1 && !strcmp(argv[1], "after-killed-leaving")) return killedWhileLeaving(NO);
    if (argc > 1 && !strcmp(argv[1], "after-killed-target")) return killedBetweenMapped(NO, 1);
    @autoreleasepool {
        clearDefaults();

        // Launch on the speaker: nothing remembered, nothing changes.
        SGAutoEqOutputChanged(kSpeaker, @"Speaker");
        check([playing() isEqualToString:@"off"], @"launch on the speaker: the Graphic EQ stays off");

        // AirPods connect, the user picks a correction and turns Use for AirPods on.
        SGAutoEqOutputChanged(kAirPods, @"AirPods Pro");
        SGAutoEqApplyText(@"crinacle/AirPods%20Pro", kLine);
        check(!SGAutoEqOutputRemembered(kAirPods), @"a pick alone remembers nothing");
        SGAutoEqRememberOutput(YES);
        check(SGAutoEqOutputRemembered(kAirPods), @"Use for AirPods Pro remembers it");
        check(SGDSPSwitch(SGKeyDSP), @"the pick turned Audio effects on");

        // Back to the speaker: the AirPods' correction goes off.
        SGAutoEqOutputChanged(kSpeaker, @"Speaker");
        check([playing() isEqualToString:@"off"], [NSString stringWithFormat:@"speaker: the AirPods' correction is off (%@)", playing()]);
        check([SGDSPString(SGKeyDSPGraphicEqHeadphone) isEqualToString:@""], @"speaker: no headphone named");

        // AirPods again: their correction comes back, nodes and all, with no download.
        SGDSPSetString(SGKeyDSPGraphicEqNodes, @"GraphicEQ: 20 0.0");
        SGAutoEqOutputChanged(kAirPods, @"AirPods Pro");
        check([playing() isEqualToString:@"crinacle/AirPods%20Pro"], [NSString stringWithFormat:@"AirPods again: their correction is on (%@)", playing()]);
        check([SGDSPString(SGKeyDSPGraphicEqNodes) isEqualToString:kLine], @"AirPods again: their own curve");

        // The same output again (a category change, not a new route): nothing happens.
        SGDSPSetSwitch(SGKeyDSPGraphicEq, NO);
        SGAutoEqOutputChanged(kAirPods, @"AirPods Pro");
        check([playing() isEqualToString:@"off"], @"the same output again changes nothing");
        SGDSPSetSwitch(SGKeyDSPGraphicEq, YES);

        // Another pair, remembered with its own correction, then the AirPods: each gets its own.
        SGAutoEqOutputChanged(kSony, @"WH-1000XM5");
        check([playing() isEqualToString:@"off"], @"a new pair with nothing remembered: the AirPods' correction goes off");
        SGAutoEqRememberOutput(YES);
        SGAutoEqApplyText(@"oratory1990/Sony%20WH-1000XM5", kSonyLine);
        SGAutoEqOutputChanged(kAirPods, @"AirPods Pro");
        check([playing() isEqualToString:@"crinacle/AirPods%20Pro"], @"AirPods: theirs");
        SGAutoEqOutputChanged(kSony, @"WH-1000XM5");
        check([playing() isEqualToString:@"oratory1990/Sony%20WH-1000XM5"] && [SGDSPString(SGKeyDSPGraphicEqNodes) isEqualToString:kSonyLine],
              @"Sony: its own pick, not the AirPods'");

        // None remembered for the Sony: a pick of None on it sticks.
        SGAutoEqTakeOff();
        SGAutoEqOutputChanged(kAirPods, @"AirPods Pro");
        SGAutoEqOutputChanged(kSony, @"WH-1000XM5");
        check([playing() isEqualToString:@"off"], @"None picked for the Sony stays None for it");

        // A correction picked on the speaker, with nothing remembered there, is the user's: it stays everywhere.
        SGAutoEqForgetOutput(kSony);
        SGAutoEqOutputChanged(kSpeaker, @"Speaker");
        SGAutoEqApplyText(@"someone/Speaker%20Fix", kLine);
        SGAutoEqOutputChanged(kSony, @"WH-1000XM5");
        check([playing() isEqualToString:@"someone/Speaker%20Fix"], @"a pick made with nothing remembered is not taken off");

        // A curve of the user's own is never taken off by a route change.
        SGAutoEqOutputChanged(kAirPods, @"AirPods Pro");
        SGDSPSetString(SGKeyDSPGraphicEqNodes, @"GraphicEQ: 100 6.0");
        SGDSPSetString(SGKeyDSPGraphicEqHeadphone, @"");
        SGAutoEqOutputChanged(kSpeaker, @"Speaker");
        check(SGDSPSwitch(SGKeyDSPGraphicEq) && [SGDSPString(SGKeyDSPGraphicEqNodes) isEqualToString:@"GraphicEQ: 100 6.0"],
              @"a hand-made curve stays on the speaker");

        // A route change never turns the effects on.
        SGDSPSetSwitch(SGKeyDSP, NO);
        SGAutoEqOutputChanged(kAirPods, @"AirPods Pro");
        check(!SGDSPSwitch(SGKeyDSP) && [playing() isEqualToString:@"crinacle/AirPods%20Pro"], @"AirPods with Audio effects off: correction set, effects left off");

        // Forgetting the AirPods: listed no more, and their correction stays until the next change.
        NSUInteger before = SGAutoEqRememberedOutputs().count;
        SGAutoEqRememberOutput(NO);
        check(!SGAutoEqOutputRemembered(kAirPods) && SGAutoEqRememberedOutputs().count == before - 1, @"Use for AirPods Pro off forgets them");
        check([playing() isEqualToString:@"crinacle/AirPods%20Pro"], @"forgetting leaves what plays");
        SGAutoEqOutputChanged(kSpeaker, @"Speaker");
        check([playing() isEqualToString:@"crinacle/AirPods%20Pro"], @"once forgotten, the speaker keeps it: it is a plain pick now");

        // A renamed output keeps its pick under its new name.
        SGAutoEqOutputChanged(kSony, @"WH-1000XM5");
        SGAutoEqRememberOutput(YES);
        SGAutoEqOutputChanged(kSpeaker, @"Speaker");
        SGAutoEqOutputChanged(kSony, @"Sony at work");
        check([SGAutoEqRememberedOutputs().firstObject[@"name"] isEqualToString:@"Sony at work"], @"a renamed output is listed by its new name");

        checkPresetPerOutput();
        clearDefaults();
        printf("%d failed\n", failures);
    }
    return failures;
}
