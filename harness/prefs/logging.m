// Observe the real logging sink through the driver's existing in-memory log.
#import <Foundation/Foundation.h>
#import "Core/SGLog.h"
#import "../harness-fail.h"

int main(void) {
    @autoreleasepool {
        NSMutableSet<NSString *> *cards = nil, *sections = nil;
        __block NSUInteger keyReads = 0;
        NSString *(^key)(void) = ^{ keyReads++; return @"same key"; };
        uint64_t start = SGLogLastSeq();
        SGLogOnce(&cards, key(), @"redesign search: %@");
        HARNESS_CHECK([[SGLogRecent(start) valueForKey:@"text"] isEqual:@[@"redesign search: same key"]]);

        uint64_t afterFirst = SGLogLastSeq();
        SGLogOnce(&cards, key(), @"must not log: %@");
        HARNESS_CHECK(SGLogRecent(afterFirst).count == 0);
        HARNESS_CHECK(keyReads == 2);

        SGLogOnce(&sections, @"same key", @"redesign search: %@");
        HARNESS_CHECK([[SGLogRecent(afterFirst) valueForKey:@"text"] isEqual:@[@"redesign search: same key"]]);
        puts("PASS once-per-message logging: repeated key suppressed; separate sets independent");
    }
    return 0;
}
