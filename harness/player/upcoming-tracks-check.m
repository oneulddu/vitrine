#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <stdlib.h>

// Only the Spotify data surface consumed by the extracted production helpers.
@interface SPTPlayerTrack : NSObject
@property (nonatomic, copy) NSString *trackTitle;
@property (nonatomic, strong) id URI;
@end
@implementation SPTPlayerTrack
@end

@interface SPTPlayerState : NSObject
@property (nonatomic, strong) id future;
@end
@implementation SPTPlayerState
@end

// A queue limit must stop enumeration before reading the next track.
@interface UnreadTrack : SPTPlayerTrack
@end
@implementation UnreadTrack
- (NSString *)trackTitle {
    NSLog(@"FAIL: inspected a track after the 50 accepted rows");
    exit(1);
}
@end

#include "player-state-data.inc"

static SPTPlayerTrack *track(NSString *title, id uri) {
    SPTPlayerTrack *value = [SPTPlayerTrack new];
    value.trackTitle = title;
    value.URI = uri;
    return value;
}

static int failures;
static void check(BOOL passed, NSString *name) {
    if (!passed) failures++;
    NSLog(@"%@: %@", passed ? @"PASS" : @"FAIL", name);
}

int main(void) {
    @autoreleasepool {
        check([SGURIString(@"spotify:track:a") isEqualToString:@"spotify:track:a"], @"string URI");
        check([SGURIString([NSURL URLWithString:@"spotify:track:b"]) isEqualToString:@"spotify:track:b"], @"URL URI");
        check(SGURIString(@7) == nil, @"reject non-string, non-URL URI");
        check([SGURIString(@"") isEqualToString:@""], @"retain empty URI");

        SPTPlayerTrack *first = track(@"First", @"spotify:track:a");
        SPTPlayerTrack *second = track(@"Second", [NSURL URLWithString:@"spotify:track:b"]);
        SPTPlayerTrack *emptyURI = track(@"Empty URI", @"");
        SPTPlayerState *state = [SPTPlayerState new];
        state.future = @[@"not a track", track(nil, @"spotify:track:x"), first,
                         track(@"", @"spotify:track:x"), track(@"No URI", nil),
                         second, track(@"Bad URI", @7), first, emptyURI];
        check([SGPlayerUpcomingTracks(state, NSUIntegerMax) isEqualToArray:@[first, second, first, emptyURI]],
              @"filter invalid entries, retaining order, duplicates and empty URI");
        check([SGPlayerUpcomingTracks(state, 2) isEqualToArray:@[first, second]], @"limit counts accepted tracks");
        state.future = @"not an array";
        check(SGPlayerUpcomingTracks(state, NSUIntegerMax).count == 0, @"reject non-array future");
        state.future = nil;
        check(SGPlayerUpcomingTracks(state, NSUIntegerMax).count == 0, @"missing future");
        check(SGPlayerUpcomingTracks((id)[NSObject new], NSUIntegerMax).count == 0, @"state without future selector");
        check(SGPlayerUpcomingTracks(nil, NSUIntegerMax).count == 0, @"no state");

        NSMutableArray *many = [NSMutableArray array];
        for (NSUInteger i = 0; i < 50; i++) [many addObject:first];
        [many addObject:[UnreadTrack new]];
        state.future = many;
        check(SGPlayerUpcomingTracks(state, 50).count == 50, @"50-row early stop");
        many[50] = second;
        check(SGPlayerUpcomingTracks(state, NSUIntegerMax).count == 51, @"unlimited list retains tracks beyond 50");
        NSLog(@"upcoming tracks: %@", failures ? @"FAIL" : @"PASS");
        return failures ? 1 : 0;
    }
}
