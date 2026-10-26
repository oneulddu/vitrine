#import "Shared/Player/SGAudioFormat.h"

int main(void) {
    @autoreleasepool {
        struct {
            AudioFormatID identifier;
            AudioFormatFlags flags;
            UInt32 bits;
            NSString *expected;
        } cases[] = {
            {kAudioFormatLinearPCM, kAudioFormatFlagIsFloat, 32,
             @"48000 Hz, 2 channels, 32-bit float, interleaved"},
            {kAudioFormatLinearPCM, kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved, 32,
             @"48000 Hz, 2 channels, 32-bit float, a buffer per channel"},
            {kAudioFormatLinearPCM, kAudioFormatFlagIsSignedInteger, 16,
             @"48000 Hz, 2 channels, 16-bit integer, interleaved"},
            {kAudioFormatLinearPCM, kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsNonInterleaved, 16,
             @"48000 Hz, 2 channels, 16-bit integer, a buffer per channel"},
            {'aac ', 0, 0, @"'aac '"},
        };
        for (NSUInteger i = 0; i < sizeof cases / sizeof cases[0]; i++) {
            AudioStreamBasicDescription format = {0};
            format.mFormatID = cases[i].identifier;
            format.mFormatFlags = cases[i].flags;
            format.mBitsPerChannel = cases[i].bits;
            format.mSampleRate = 48000;
            format.mChannelsPerFrame = 2;
            NSString *actual = SGAudioFormatText(format);
            if (![actual isEqualToString:cases[i].expected]) {
                NSLog(@"FAIL audio format %lu: expected %@, got %@", (unsigned long)i, cases[i].expected, actual);
                return 1;
            }
        }
        NSLog(@"PASS audio format: five exact output cases");
        return 0;
    }
}
