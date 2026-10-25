#pragma once
#import <Foundation/Foundation.h>

// Read-only requests preserve the log cursor established by the last action.
static inline BOOL SGDriverCommandIsReadOnly(NSString *command, NSDictionary *params) {
    if ([command isEqualToString:@"pref"])
        return !params[@"value"] && !params[@"text"] && !params[@"remove"];
    return [[NSSet setWithArray:@[@"find", @"state", @"screenshot", @"log", @"wait", @"pip.frame"]]
        containsObject:command];
}
