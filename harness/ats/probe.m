// Loads the app's real App Transport Security policy from its own bundle and asks URLSession for
// each address. ATS decides before any connection, so a refused request fails with
// NSURLErrorAppTransportSecurityRequiresSecureConnection; any other answer means the policy did not
// refuse that address, which is all a network error proves. A probe that never answered (a semaphore
// timeout) prints its own sentinel and proves nothing, so the checker reports it inconclusive or a
// failure rather than an allow.
#import <Foundation/Foundation.h>

static NSString *const kATSRefused = @"ATS-refused";
static NSString *const kProbeExpired = @"probe-expired";

static NSString *probe(NSString *url) {
    dispatch_semaphore_t wait = dispatch_semaphore_create(0);
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForRequest = 3;
    config.timeoutIntervalForResource = 3;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    __block NSString *outcome = nil;
    [[session dataTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        (void)data;
        NSString *result;
        if (!error) result = [NSString stringWithFormat:@"HTTP %ld", (long)([response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0)];
        else if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorAppTransportSecurityRequiresSecureConnection) result = kATSRefused;
        else result = [NSString stringWithFormat:@"%@/%ld", error.domain, (long)error.code];
        outcome = result;
        dispatch_semaphore_signal(wait);
    }] resume];
    // After a timeout the completion handler may still run and write `outcome`, so this path never
    // reads it: the sentinel is returned directly and the session is cancelled.
    if (dispatch_semaphore_wait(wait, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) != 0) {
        [session invalidateAndCancel];
        return kProbeExpired;
    }
    [session invalidateAndCancel];
    return outcome ?: kProbeExpired;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        // Usage: probe <url>...   Each line: "<url>\t<outcome>".
        for (int i = 1; i < argc; i++) {
            NSString *url = [NSString stringWithUTF8String:argv[i]];
            printf("%s\t%s\n", url.UTF8String, probe(url).UTF8String);
            fflush(stdout);
        }
    }
    return 0;
}
