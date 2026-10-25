#import "Diagnostics/SGDriverAuth.h"
#import "Core/SGPrefs.h"
#import "App/About/SGDiagnosticRedaction.h"
#import "../harness-fail.h"

static void checkRotation(BOOL migrated) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    id beforeToken = [store objectForKey:SGKeyDriverToken];
    id beforeMarker = [store objectForKey:SGKeyDriverTokenRotated];
    id beforeLegacy = [store objectForKey:@"spotifyglass.driver.token.rotated"];
    NSString *fixture = @"0123456789abcdef0123456789abcdef";
    [store setObject:fixture forKey:SGKeyDriverToken];
    // An old wildcard backup can pre-seed this marker along with a known credential.
    [store setBool:YES forKey:@"spotifyglass.driver.token.rotated"];
    if (migrated) [store setBool:YES forKey:SGKeyDriverTokenRotated];
    else [store removeObjectForKey:SGKeyDriverTokenRotated];
    NSString *token = SGDriverToken();
    BOOL marked = [store boolForKey:SGKeyDriverTokenRotated];
    BOOL legacyRemoved = [store objectForKey:@"spotifyglass.driver.token.rotated"] == nil;
    // Restore the host harness's preferences before reporting any failure.
    if (beforeToken) [store setObject:beforeToken forKey:SGKeyDriverToken];
    else [store removeObjectForKey:SGKeyDriverToken];
    if (beforeMarker) [store setObject:beforeMarker forKey:SGKeyDriverTokenRotated];
    else [store removeObjectForKey:SGKeyDriverTokenRotated];
    if (beforeLegacy) [store setObject:beforeLegacy forKey:@"spotifyglass.driver.token.rotated"];
    else [store removeObjectForKey:@"spotifyglass.driver.token.rotated"];
    HARNESS_CHECK(legacyRemoved);
    HARNESS_CHECK(marked);
    HARNESS_CHECK(token.length == 32);
    if (migrated) HARNESS_CHECK([token isEqualToString:@"0123456789abcdef0123456789abcdef"]);
    else HARNESS_CHECK(![token isEqualToString:@"0123456789abcdef0123456789abcdef"]);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        checkRotation(argc > 1 && strcmp(argv[1], "migrated") == 0);
        NSString *token = @"0123456789abcdef0123456789abcdef";
        HARNESS_CHECK(SGDriverRequestAuthorized(@"GET /state HTTP/1.1\r\nx-phone-token:\t0123456789abcdef0123456789abcdef \r\n\r\n", token));
        HARNESS_CHECK(!SGDriverRequestAuthorized(@"GET /state HTTP/1.1\r\nX-Phone-Token: 0123456789ABCDEF0123456789ABCDEF\r\n\r\n", token));
        HARNESS_CHECK(!SGDriverRequestAuthorized(@"GET /state HTTP/1.1\r\nX-Phone-Token: 0123456789abcdef0123456789abcdef\r\nx-phone-token: 0123456789abcdef0123456789abcdef\r\n\r\n", token));
        HARNESS_CHECK(!SGDriverRequestAuthorized(@"GET /state HTTP/1.1\r\nHost: phone\r\n\r\nX-Phone-Token: 0123456789abcdef0123456789abcdef\r\n", token));
        HARNESS_CHECK(!SGDriverRequestAuthorized(@"GET /state HTTP/1.1\r\nX-Phone-Token: short\r\n\r\n", token));
        HARNESS_CHECK(!SGDriverRequestAuthorized(@"GET /state HTTP/1.1\r\nX-Phone-Token: short\r\n\r\n", @"short"));
        NSString *longToken = [token stringByAppendingString:[@"" stringByPaddingToLength:256 withString:@"x" startingAtIndex:0]];
        NSString *longRequest = [NSString stringWithFormat:@"GET /state HTTP/1.1\r\nX-Phone-Token: %@\r\n\r\n", longToken];
        HARNESS_CHECK(!SGDriverRequestAuthorized(longRequest, token));
        HARNESS_CHECK(!SGDriverRequestAuthorized(longRequest, longToken));
        HARNESS_CHECK(!SGDriverRequestAuthorized(@"GET /state HTTP/1.1\r\nX-Phone-Token: 0123456789abcdef0123456789abcdef0\r\n\r\n", token));
        HARNESS_CHECK(!SGDriverRequestAuthorized(@"GET /state HTTP/1.1\r\nX-Phone-Token: 0123456789abcdef0123456789abcdee\r\n\r\n", token));
        HARNESS_CHECK(!SGDriverRequestAuthorized(@"GET /state HTTP/1.1\r\nX-Phone-Token: 0123456789abcdef0123456789abcdef\r\n extra\r\n\r\n", token));
        HARNESS_CHECK(!SGDriverRequestAuthorized(@"GET /state HTTP/1.1\r\nX-Phone-Token: 0123456789abcdef0123456789abcdef\r\n", token));
        NSDictionary *private = @{
            @"spotifyglass.driver.token": @"driver-fixture",
            @"spotifyglass.musixmatch.token": @"music-fixture",
            @"spotifyglass.motion.token": @"motion-fixture",
        };
        NSString *diagnostics = @"keep\nspotifyglass.driver.token=driver-fixture\nspotifyglass.musixmatch.token=music-fixture\nspotifyglass.motion.token=motion-fixture\nvitrine.private.driver.token.rotated\nspotifyglass.driver.token.rotated\n";
        HARNESS_CHECK([SGRedactDiagnostics(diagnostics, private) isEqualToString:@"keep\n[redacted]=[redacted]\n[redacted]=[redacted]\n[redacted]=[redacted]\n[redacted]\n[redacted]\n"]);
        HARNESS_CHECK([SGRedactDiagnostics(@"before\ndriver: tailnet listener on phone:8085, token old-fixture\nafter", @{}) isEqualToString:@"before\n[redacted]\nafter"]);
        HARNESS_CHECK([SGRedactDiagnostics(@"prefix secret\nline suffix", @{@"spotifyglass.motion.token": @"secret\nline"}) isEqualToString:@"prefix [redacted] suffix"]);
        HARNESS_CHECK([SGRedactDiagnostics(@"ordinary", @{@"spotifyglass.title": @"ordinary"}) isEqualToString:@"ordinary"]);
        puts("driver auth: PASS");
    }
    return 0;
}
