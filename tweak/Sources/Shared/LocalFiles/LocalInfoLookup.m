#import "LocalInfoLookup.h"
#import <math.h>

const NSUInteger SGLocalInfoJSONLimit = 2 * 1024 * 1024;
const NSUInteger SGLocalInfoCoverLimit = 4 * 1024 * 1024;
static const NSTimeInterval kRequestTimeoutSeconds = 15;
static const double kDurationToleranceMilliseconds = 3000;
static const NSUInteger kSearchCacheEntries = 32;
// Main-thread-only FIFO, keyed by the complete request URL (including term and country).
static NSMutableDictionary<NSString *, NSArray<NSDictionary *> *> *searchCache;
static NSMutableArray<NSString *> *searchOrder;

static BOOL allowedURL(NSURL *url, BOOL search) {
    NSString *host = url.host.lowercaseString;
    BOOL trustedHost = search ? [host isEqual:@"itunes.apple.com"] :
        ([host isEqual:@"mzstatic.com"] || [host hasSuffix:@".mzstatic.com"]);
    return [url.scheme.lowercaseString isEqual:@"https"] && !url.user && !url.password && trustedHost;
}

static NSString *replace(NSString *text, NSString *pattern, NSString *replacement) {
    return [text stringByReplacingOccurrencesOfString:pattern withString:replacement
                                              options:NSRegularExpressionSearch range:NSMakeRange(0, text.length)];
}

static NSString *clean(NSString *text) {
    NSString *previous;
    do {
        previous = text;
        text = replace(text, @"\\([^()]*\\)|\\[[^\\[\\]]*\\]", @" ");
    } while (![text isEqual:previous]);
    text = replace(text, @"^\\s*\\d{1,3}(?:[\\s._-]+)", @"");
    text = replace(text, @"(?i)\\b(?:official|video|audio|lyrics|lyric|hd|hq|4k|visualizer|explicit|remastered|remaster)\\b", @" ");
    return [replace(text, @"\\s+", @" ") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

NSString *SGLocalInfoQuery(NSString *title, NSString *artist, NSString *filename) {
    title = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    artist = [artist stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    if (!title.length && !artist.length) return clean(filename.lastPathComponent.stringByDeletingPathExtension ?: @"");
    return clean([NSString stringWithFormat:@"%@ %@", title, artist]);
}

NSURL *SGLocalInfoSearchURL(NSString *query, NSString *region) {
    NSURLComponents *url = [NSURLComponents componentsWithString:@"https://itunes.apple.com/search"];
    NSMutableArray *items = [NSMutableArray arrayWithArray:@[
        [NSURLQueryItem queryItemWithName:@"term" value:query],
        [NSURLQueryItem queryItemWithName:@"media" value:@"music"],
        [NSURLQueryItem queryItemWithName:@"entity" value:@"song"],
        [NSURLQueryItem queryItemWithName:@"limit" value:@"10"]]];
    if (region.length) [items addObject:[NSURLQueryItem queryItemWithName:@"country" value:region.lowercaseString]];
    url.queryItems = items;
    return url.URL;
}

NSString *SGLocalInfoArtworkURL(NSString *url) {
    if (![url isKindOfClass:NSString.class]) return nil;
    if (!allowedURL([NSURL URLWithString:url], NO)) return nil;
    return [url stringByReplacingOccurrencesOfString:@"100x100bb" withString:@"600x600bb"];
}

static NSString *text(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

NSArray<NSDictionary *> *SGLocalInfoParse(NSData *data) {
    if (!data.length || data.length > SGLocalInfoJSONLimit) return nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![root isKindOfClass:NSDictionary.class] || ![root[@"results"] isKindOfClass:NSArray.class]) return nil;
    NSMutableArray *songs = [NSMutableArray array];
    for (id row in root[@"results"]) {
        if (![row isKindOfClass:NSDictionary.class]) continue;
        id duration = row[@"trackTimeMillis"];
        if (![duration isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)duration) == CFBooleanGetTypeID() ||
            !isfinite([duration doubleValue]) || [duration doubleValue] <= 0) continue;
        NSString *title = text(row[@"trackName"]);
        if (!title.length) continue;
        NSString *date = text(row[@"releaseDate"]);
        NSString *year = [date rangeOfString:@"^[0-9]{4}-" options:NSRegularExpressionSearch].location == 0 ?
            [date substringToIndex:4] : @"";
        [songs addObject:@{@"title": title, @"artist": text(row[@"artistName"]), @"album": text(row[@"collectionName"]),
                           @"year": year, @"milliseconds": duration,
                           @"cover": SGLocalInfoArtworkURL(row[@"artworkUrl100"]) ?: @""}];
    }
    return songs;
}

static NSSet *tokens(NSString *value) {
    NSString *folded = [(value ?: @"") stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch
                                                       locale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    NSArray *parts = [folded componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet];
    NSMutableSet *result = [NSMutableSet setWithArray:parts];
    [result removeObject:@""];
    return result;
}

static double similarity(NSString *a, NSString *b) {
    NSSet *left = tokens(a), *right = tokens(b);
    NSMutableSet *intersection = [left mutableCopy], *all = [left mutableCopy];
    [intersection intersectSet:right];
    [all unionSet:right];
    return all.count ? (double)intersection.count / all.count : 0;
}

NSArray<NSDictionary *> *SGLocalInfoRank(NSArray<NSDictionary *> *songs, NSString *title,
                                        NSString *artist, NSTimeInterval seconds) {
    NSMutableArray *eligible = [NSMutableArray array];
    for (NSDictionary *song in songs) {
        double distance = fabs([song[@"milliseconds"] doubleValue] - seconds * 1000);
        if (seconds > 0 && distance > kDurationToleranceMilliseconds) continue;
        [eligible addObject:song];
    }
    return [eligible sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        for (NSString *field in @[@"title", @"artist"]) {
            NSString *current = [field isEqual:@"title"] ? title : artist;
            double first = similarity(current, a[field]), second = similarity(current, b[field]);
            if (first != second) return first > second ? NSOrderedAscending : NSOrderedDescending;
        }
        if (seconds > 0) {
            double first = fabs([a[@"milliseconds"] doubleValue] - seconds * 1000);
            double second = fabs([b[@"milliseconds"] doubleValue] - seconds * 1000);
            if (first != second) return first < second ? NSOrderedAscending : NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
}

@implementation SGLocalInfoLookup {
    NSURLSession *_session;
    NSURLSessionDataTask *_task;
    NSMutableData *_body;
    NSUInteger _limit;
    BOOL _searchRequest, _parsing;
    NSUInteger _generation;
    void (^_completion)(NSData *, NSError *);
}

- (BOOL)busy { return _task != nil || _parsing; }

- (void)search:(NSURL *)url completion:(void (^)(NSArray<NSDictionary *> *, NSError *))completion {
    if (self.busy) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        searchCache = [NSMutableDictionary dictionary];
        searchOrder = [NSMutableArray array];
    });
    NSString *key = url.absoluteString;
    NSArray *cached = key ? searchCache[key] : nil;
    if (cached) { completion(cached, nil); return; }
    __weak typeof(self) weakSelf = self;
    [self start:url limit:SGLocalInfoJSONLimit search:YES completion:^(NSData *data, NSError *error) {
        SGLocalInfoLookup *owner = weakSelf;
        if (!owner) return;
        if (error) { completion(nil, error); return; }
        owner->_parsing = YES;
        NSUInteger generation = owner->_generation;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSArray *songs = SGLocalInfoParse(data);
            dispatch_async(dispatch_get_main_queue(), ^{
                SGLocalInfoLookup *owner = weakSelf;
                if (!owner || generation != owner->_generation) return;
                owner->_parsing = NO;
                if (!songs) {
                    completion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotParseResponse userInfo:nil]);
                    return;
                }
                if (!searchCache[key]) {
                    if (searchOrder.count == kSearchCacheEntries) {
                        [searchCache removeObjectForKey:searchOrder.firstObject];
                        [searchOrder removeObjectAtIndex:0];
                    }
                    [searchOrder addObject:key];
                }
                searchCache[key] = songs;
                completion(songs, nil);
            });
        });
    }];
}

- (void)cover:(NSURL *)url completion:(void (^)(NSData *, NSError *))completion {
    [self start:url limit:SGLocalInfoCoverLimit search:NO completion:completion];
}

- (void)start:(NSURL *)url limit:(NSUInteger)limit search:(BOOL)search completion:(void (^)(NSData *, NSError *))completion {
    if (self.busy) return;
    if (!allowedURL(url, search)) {
        completion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil]);
        return;
    }
    _searchRequest = search;
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForRequest = kRequestTimeoutSeconds;
    config.timeoutIntervalForResource = kRequestTimeoutSeconds;
    config.HTTPCookieStorage = nil;
    config.HTTPShouldSetCookies = NO;
    config.URLCache = nil;
    config.allowsConstrainedNetworkAccess = NO;
    _body = [NSMutableData data];
    _limit = limit;
    _completion = [completion copy];
    // Delegate traffic is serial on main; only bounded byte appends happen here, never JSON or image decoding.
    _session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:NSOperationQueue.mainQueue];
    _task = [_session dataTaskWithURL:url];
    [_task resume];
}

- (void)cancel {
    ++_generation;
    _parsing = NO;
    _completion = nil;
    [_session invalidateAndCancel];
    _task = nil;
    _session = nil;
    _body = nil;
}

- (void)finish:(NSError *)error {
    void (^completion)(NSData *, NSError *) = _completion;
    NSData *body = [_body copy];
    [self cancel];
    if (completion) completion(error ? nil : body, error);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
 didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    if (task != _task) { completionHandler(NSURLSessionResponseCancel); return; }
    NSInteger status = [(NSHTTPURLResponse *)response statusCode];
    if (status < 200 || status >= 300 || response.expectedContentLength > (int64_t)_limit) {
        completionHandler(NSURLSessionResponseCancel);
        [self finish:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadServerResponse userInfo:nil]];
    } else completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (task != _task) return;
    if (data.length > _limit - _body.length) {
        [self finish:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorDataLengthExceedsMaximum userInfo:nil]];
        return;
    }
    [_body appendData:data];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (task == _task) [self finish:error];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
 willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    if (task != _task) { completionHandler(nil); return; }
    if (!allowedURL(request.URL, _searchRequest)) {
        completionHandler(nil);
        [self finish:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil]];
        return;
    }
    completionHandler(request);
}
@end
