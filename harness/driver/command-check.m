#import "Diagnostics/SGDriverCommand.h"
#import "Core/SGLog.h"
#import "../harness-fail.h"

// Exercise the driver's command classification with its real log ring, without UIKit or a phone.
int main(void) {
    @autoreleasepool {
        NSDictionary *discovery = @{@"key": @"spotifyglass.driver.token"};
        for (NSString *parameter in @[@"value", @"text", @"remove"]) {
            // Even an empty text or a zero-valued remove parameter is a mutation.
            HARNESS_CHECK(!SGDriverCommandIsReadOnly(@"pref", @{@"key": @"spotifyglass.test", parameter: @""}));
        }
        HARNESS_CHECK(!SGDriverCommandIsReadOnly(@"tap", @{}));
        for (NSString *command in @[@"find", @"state", @"screenshot", @"log", @"wait", @"pip.frame"])
            HARNESS_CHECK(SGDriverCommandIsReadOnly(command, @{}));

        uint64_t actionSeq = 0;
        SGLogRemember(@"before action");
        NSArray *commands = @[@"pref", @"tap", @"pref", @"wait"];
        for (NSString *command in commands) {
            NSDictionary *params = [command isEqualToString:@"pref"] ? discovery : @{};
            if (!SGDriverCommandIsReadOnly(command, params)) actionSeq = SGLogLastSeq();
            if ([command isEqualToString:@"tap"]) SGLogRemember(@"action completed");
            if ([command isEqualToString:@"wait"]) {
                NSArray *lines = SGLogRecent(actionSeq);
                HARNESS_CHECK(lines.count == 1);
                HARNESS_CHECK([lines[0][@"text"] isEqualToString:@"action completed"]);
            }
        }
        NSLog(@"driver command checks passed");
    }
    return 0;
}
