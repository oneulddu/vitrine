#import "App/About/About.h"
#import "Core/SGPrefs.h"
#import "../harness-fail.h"

static void stored(NSArray *releases, BOOL betas) {
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{
        @"spotifyglass.update.releases": releases,
        @"spotifyglass.update.checked": @1,
        SGKeyUpdateBetas: @(betas),
    } forName:NSArgumentDomain];
    SGPrefsChanged();
}

int main(void) {
    @autoreleasepool {
        NSArray *releases = @[
            @"not a release",
            @{},
            @{@"version": @"3.0.0", @"prerelease": @YES, @"notes": @"### Features\n* Preview"},
            @{@"version": @"2.5.0-beta.1", @"notes": @"### Features\n* Unmarked beta"},
            @{@"version": @"2.0.0", @"prerelease": @NO, @"notes": @"### Fixes\n* Stable"},
        ];
        stored(releases, NO);
        HARNESS_CHECK([SGUpdateVersion() isEqualToString:@"2.0.0"]);
        stored(releases, YES);
        HARNESS_CHECK([SGUpdateVersion() isEqualToString:@"3.0.0"]);
        stored(@[@{@"version": @"0.9.0", @"notes": @"### Fixes\n* Old"}], YES);
        HARNESS_CHECK(SGUpdateVersion() == nil);
        stored(@[], NO);
        HARNESS_CHECK(SGUpdateVersion() == nil);
        NSLog(@"[harness] offline update selection PASS");
    }
    return 0;
}
