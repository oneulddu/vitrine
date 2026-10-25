// Host check for Core/SGPrefs.m's memo: a write applies to the next read, through the accessors or straight
// to NSUserDefaults, from this thread or another, and an unset key reads as its fallback.
#import <Foundation/Foundation.h>
#import "Core/SGPrefs.h"
#import "../harness-fail.h"

#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #cond); exit(1); } } while (0)

int main(void) {
    @autoreleasepool {
        for (NSString *key in @[@"spotifyglass.driver.token", @"spotifyglass.driver.token.rotated",
                                @"vitrine.private.driver.token.rotated",
                                @"spotifyglass.musixmatch.token", @"spotifyglass.motion.token"])
            HARNESS_CHECK(SGPrivatePreferenceKey(key));
        HARNESS_CHECK(!SGPrivatePreferenceKey(@"spotifyglass.redesign"));
        HARNESS_CHECK(!SGPrivatePreferenceKey(@"spotifyglass.motion.sources"));

        NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
        NSString *flag = @"spotifyglass.test.flag", *choice = @"spotifyglass.test.int";
        for (NSString *key in @[flag, choice, SGKeyStock]) [store removeObjectForKey:key];

        CHECK(SGEnabled(flag) && !SGHidden(flag));
        CHECK(SGInt(choice, 7) == 7);
        SGSetEnabled(flag, NO);
        CHECK(!SGEnabled(flag));
        SGSetInt(choice, 3);
        CHECK(SGInt(choice, 7) == 3);

        [store setBool:YES forKey:flag];
        CHECK(SGHidden(flag));
        [store removeObjectForKey:flag];
        CHECK(SGEnabled(flag));
        [store setBool:YES forKey:SGKeyStock];
        CHECK(!SGEnabled(flag) && !SGFlag(flag, YES));
        [store removeObjectForKey:SGKeyStock];
        CHECK(SGEnabled(flag));

        dispatch_sync(dispatch_get_global_queue(0, 0), ^{ [store setInteger:9 forKey:choice]; });
        CHECK(SGInt(choice, 7) == 9);
        [store removeObjectForKey:choice];
        CHECK(SGInt(choice, 7) == 7);

        // Imported property-list containers and other nonscalar values read as unset, even for
        // the stock marker. Catch an old reader's exception so a regression exits without a crash.
        @try {
            for (id invalid in @[@[], @{}, [NSData data], [NSDate dateWithTimeIntervalSince1970:0]]) {
                [store setObject:invalid forKey:flag];
                HARNESS_CHECK(SGFlag(flag, YES));
                HARNESS_CHECK(!SGFlag(flag, NO));
                [store setObject:invalid forKey:choice];
                HARNESS_CHECK(SGInt(choice, 7) == 7);
            }
            [store setObject:@{} forKey:SGKeyStock];
            HARNESS_CHECK(SGEnabled(flag));
            [store setBool:YES forKey:SGKeyStock];
            HARNESS_CHECK(!SGEnabled(flag));
            [store setObject:@"YES" forKey:flag];
            HARNESS_CHECK(SGHidden(flag));
            [store setObject:@"12" forKey:choice];
            HARNESS_CHECK(SGInt(choice, 7) == 12);
        } @catch (NSException *exception) {
            HARNESS_FAIL(@"Malformed preference raised %@", exception.reason);
        }
        [store removeObjectForKey:SGKeyStock];

        for (NSString *key in @[flag, choice]) [store removeObjectForKey:key];
        CHECK(!SGRestartPending());
        SGRestartSpotify();
        dispatch_sync(dispatch_get_global_queue(0, 0), ^{ CHECK(SGRestartPending()); });
        puts("prefs: ok");
    }
    return 0;
}
