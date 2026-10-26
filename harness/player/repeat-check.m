#import <Foundation/Foundation.h>

// Only the Spotify surface the extracted production helper consumes.
@protocol SPTPlayer <NSObject>
- (id)setRepeatingContext:(BOOL)on;
- (id)setRepeatingTrack:(BOOL)on;
@end

@interface SPTPlayerOptions : NSObject
@property (nonatomic, readonly) BOOL repeatingContext;
@property (nonatomic, readonly) BOOL repeatingTrack;
@end
@implementation SPTPlayerOptions
@end

#include "player-state-repeat.inc"

// Records the commands in the order they arrive and answers each with its own token, so the caller's
// answer says which command it was taken from.
@interface FakePlayer : NSObject <SPTPlayer>
@property (nonatomic, strong) NSMutableArray<NSString *> *calls;
- (NSString *)setRepeatingContext:(BOOL)on;
- (NSString *)setRepeatingTrack:(BOOL)on;
@end
@implementation FakePlayer
- (instancetype)init {
    if ((self = [super init])) _calls = [NSMutableArray array];
    return self;
}
- (NSString *)setRepeatingContext:(BOOL)on {
    [_calls addObject:[NSString stringWithFormat:@"context %d", on]];
    return @"context";
}
- (NSString *)setRepeatingTrack:(BOOL)on {
    [_calls addObject:[NSString stringWithFormat:@"track %d", on]];
    return @"track";
}
@end

static SPTPlayerOptions *options(BOOL context, BOOL track) {
    SPTPlayerOptions *value = [SPTPlayerOptions new];
    // The double's options are fixed at construction, as Spotify's are.
    [value setValue:@(context) forKey:@"repeatingContext"];
    [value setValue:@(track) forKey:@"repeatingTrack"];
    return value;
}

static int failures;
static void check(BOOL passed, NSString *name) {
    if (!passed) failures++;
    NSLog(@"%@: %@", passed ? @"PASS" : @"FAIL", name);
}

static BOOL order(FakePlayer *player, NSArray<NSString *> *expected) {
    return [player.calls isEqualToArray:expected];
}

int main(void) {
    @autoreleasepool {
        FakePlayer *player = [FakePlayer new];

        check([SGPlayerAdvanceRepeat(player, options(NO, NO)) isEqualToString:@"context"], @"off: the context command's answer");
        check(order(player, @[@"context 1"]), @"off: turns the context on and nothing else");

        [player.calls removeAllObjects];
        check([SGPlayerAdvanceRepeat(player, options(YES, NO)) isEqualToString:@"track"], @"the context: the track command's answer");
        check(order(player, @[@"track 1"]), @"the context: turns the track on alone");

        [player.calls removeAllObjects];
        check([SGPlayerAdvanceRepeat(player, options(YES, YES)) isEqualToString:@"context"], @"the track: the context command's answer");
        check(order(player, @[@"track 0", @"context 0"]), @"the track: the track off first, then the context");

        [player.calls removeAllObjects];
        check([SGPlayerAdvanceRepeat(player, options(NO, YES)) isEqualToString:@"context"], @"the track without the context: the context command's answer");
        check(order(player, @[@"track 0", @"context 0"]), @"the track wins over the context flag alone");

        check(SGPlayerAdvanceRepeat(nil, nil) == nil, @"no player and no options: nothing sent, nil");
        check(SGPlayerAdvanceRepeat(player, nil) != nil, @"no options: the context turned on");

        NSLog(@"repeat transition: %@", failures ? @"FAIL" : @"PASS");
        return failures ? 1 : 0;
    }
}
