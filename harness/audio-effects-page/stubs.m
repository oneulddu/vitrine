// The engine side of AudioEffects.h (AudioEffects.x in the tweak) the harness does not compile: a made-up
// status and a few fixture files in the app's library. The curves are the engine's own (SGDSPFilters.m).
// The page draws what these answer, so they answer the way the engine is documented to.
#import "Core/SGCore.h"
#import "AudioEffects.h"
#import "AudioEffectsApply.h"
#import "SGDSPFilters.h"

void SGDSPApply(NSString *effect) {
    NSLog(@"[harness] apply %@", effect);
}

NSString *SGDSPStatus(void) {
    if (!SGDSPSwitch(SGKeyDSP)) return @"Off";
    // Alternates, so the page's once a second refresh can be seen working.
    return (long)NSDate.date.timeIntervalSince1970 % 6 < 3 ? @"Running · 44.1 kHz · 3% load" : @"Running · 44.1 kHz · 4% load";
}

// A chosen file whose name has "broken" in it did not take, the way a script that does not compile would not.
NSString *SGDSPError(NSString *switchKey) {
    NSDictionary<NSString *, NSString *> *files = @{
        SGKeyDSPLiveprog: SGKeyDSPLiveprogFile, SGKeyDSPConvolver: SGKeyDSPConvolverFile, SGKeyDSPDDC: SGKeyDSPDDCFile,
    };
    NSString *fileKey = files[switchKey];
    if (fileKey && [SGDSPString(fileKey) containsString:@"broken"]) {
        return @"Line 14: syntax error: 'spl0 =  <!> ;'";
    }
    if ([switchKey isEqualToString:SGKeyDSPGraphicEq] && ![SGDSPString(SGKeyDSPGraphicEqNodes) hasPrefix:@"GraphicEQ:"]) {
        return @"Not a GraphicEQ line: it starts with \"GraphicEQ:\"";
    }
    return nil;
}

#pragma mark - file libraries

void SGHarnessSeedLibrary(SGDSPFileKind kind) {
    NSString *path = SGDSPLibraryDirectory(kind);
    NSFileManager *files = NSFileManager.defaultManager;
    if ([files contentsOfDirectoryAtPath:path error:nil].count) return;
    NSArray<NSString *> *shipped = kind == SGDSPFileImpulseResponse ? @[@"Concert hall.wav", @"Headphone crossfeed.irs", @"Small room.flac"]
                                 : kind == SGDSPFileDDC ? @[@"Beyerdynamic DT 770.vdc", @"Sennheiser HD 600.vdc"]
                                 : @[@"Bass enhancer.eel", @"Stereo panning.eel", @"Tape saturation broken.eel", @"Vinyl noise.eel"];
    for (NSString *name in shipped) {
        [[@"stand-in" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[path stringByAppendingPathComponent:name] atomically:YES];
    }
}

#pragma mark - curves

void SGDSPEqualizerResponse(NSArray<NSNumber *> *gains, NSInteger count, double *frequencies, double *decibels) {
    double values[15] = {0};
    for (NSUInteger i = 0; i < 15 && i < gains.count; i++) values[i] = gains[i].doubleValue;
    SGBiquad bands[15];
    SGDSPDesignEqualizer(48000, SGDSPEqualizerFrequencies, values, bands);
    SGDSPLogFrequencies((int)count, frequencies);
    for (NSInteger i = 0; i < count; i++) decibels[i] = SGBiquadGainDB(bands, 15, 48000, frequencies[i]);
}

void SGDSPCompanderResponse(NSArray<NSNumber *> *gains, NSInteger count, double *frequencies, double *values) {
    double amounts[7] = {0};
    for (NSUInteger i = 0; i < 7 && i < gains.count; i++) amounts[i] = gains[i].doubleValue;
    SGDSPLogFrequencies((int)count, frequencies);
    for (NSInteger i = 0; i < count; i++) values[i] = SGDSPSmoothCurve(SGDSPCompanderFrequencies, amounts, 7, frequencies[i]);
}
