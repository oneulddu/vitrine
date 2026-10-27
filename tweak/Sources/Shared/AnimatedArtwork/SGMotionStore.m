// Remote videos kept as local files in Caches/Vitrine/Motion, named by a hash of their address, and the
// videos the mod makes, named by a hash of their key. A video asked for again while it downloads joins the
// download in flight. The folder keeps the newest kFiles.
#import <AVFoundation/AVFoundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>
#import <stdlib.h>
#import <string.h>
#import "Core/SGCore.h"
#import "AnimatedArtwork.h"

static const NSUInteger kFiles = 40;
static NSCountedSet<NSString *> *sg_inUse; // store queue only; counts retained handoff URLs
static void trim(void);

static NSURL *folder(void) {
    NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    return [caches URLByAppendingPathComponent:@"Vitrine/Motion" isDirectory:YES];
}

static dispatch_queue_t storeQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("vitrine.motion.store", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

// The URL is the consumer's existing ownership handle. Its lease does not retain the
// URL, so dropping the last consumer releases the pin without a second lifecycle API.
@interface SGMotionFileLease : NSObject
@property (nonatomic, copy) NSString *path;
@end
@implementation SGMotionFileLease
- (void)dealloc {
    NSString *path = _path;
    dispatch_async(storeQueue(), ^{
        [sg_inUse removeObject:path];
        trim();
    });
}
@end

static void handOff(NSURL *file) {
    [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate: NSDate.date} ofItemAtPath:file.path error:nil];
    [file removeCachedResourceValueForKey:NSURLContentModificationDateKey];
    static char leaseKey;
    if (objc_getAssociatedObject(file, &leaseKey)) return;
    if (!sg_inUse) sg_inUse = [NSCountedSet set];
    SGMotionFileLease *lease = [SGMotionFileLease new];
    // Directory enumeration resolves aliases (for example /tmp to /private/tmp).
    // Use the same physical identity for both handoffs and trimming.
    lease.path = file.URLByResolvingSymlinksInPath.path;
    [sg_inUse addObject:lease.path];
    objc_setAssociatedObject(file, &leaseKey, lease, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static NSURL *localFor(NSString *key) {
    NSData *address = [key dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(address.bytes, (CC_LONG)address.length, digest);
    NSMutableString *name = [NSMutableString string];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [name appendFormat:@"%02x", digest[i]];
    return [folder() URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"mp4"]];
}

static void trim(void) {
    NSArray<NSURLResourceKey> *keys = @[NSURLContentModificationDateKey];
    NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder() includingPropertiesForKeys:keys
                                                                             options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    if (files.count <= kFiles) return;
    NSArray<NSURL *> *oldestFirst = [files sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        NSDate *left = nil, *right = nil;
        [a getResourceValue:&left forKey:NSURLContentModificationDateKey error:nil];
        [b getResourceValue:&right forKey:NSURLContentModificationDateKey error:nil];
        return [left compare:right];
    }];
    NSUInteger excess = files.count - kFiles;
    for (NSURL *file in oldestFirst) {
        if (!excess) break;
        if ([sg_inUse containsObject:file.URLByResolvingSymlinksInPath.path]) continue;
        if ([NSFileManager.defaultManager removeItemAtURL:file error:nil]) excess--;
    }
}

CGFloat SGMotionPixels(void) {
    return round(UIScreen.mainScreen.nativeBounds.size.width * 0.75);
}

NSURL *SGMotionMadeFile(NSString *key) {
    return localFor([@"made\n" stringByAppendingString:key]);
}

void SGMotionMakeFile(NSURL *file, BOOL (^write)(void), void (^done)(BOOL)) {
    dispatch_async(storeQueue(), ^{
        BOOL ok = [NSFileManager.defaultManager fileExistsAtPath:file.path];
        if (!ok) {
            ok = [NSFileManager.defaultManager createDirectoryAtURL:folder() withIntermediateDirectories:YES attributes:nil error:nil];
            if (ok) { trim(); ok = write(); }
        }
        if (ok) { handOff(file); trim(); }
        done(ok);
    });
}

static NSMutableDictionary<NSURL *, NSMutableArray *> *sg_waiting;

// Decimal MB, shared by every remote clip consumer. Reject advertised oversize
// bodies at the headers, and enforce the same ceiling for chunked/lying servers.
static const uint64_t kMaximumClipBytes = 30 * 1000 * 1000;
static void download(NSURL *remote, NSURL *local, NSUInteger retries);

@interface SGMotionDownload : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURL *remote, *local, *temporary;
@property (nonatomic, strong) NSFileHandle *output;
@property (nonatomic) NSUInteger retries;
@property (nonatomic) uint64_t received;
@property (nonatomic) NSInteger status;
@property (nonatomic) BOOL rejected;
@end

@implementation SGMotionDownload
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
    didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {
    self.status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    if (response.expectedContentLength > (int64_t)kMaximumClipBytes) {
        self.rejected = YES;
        completion(NSURLSessionResponseCancel);
        return;
    }
    if (self.status != 200) { completion(NSURLSessionResponseAllow); return; }
    // A unique partial outside the cache: trimming cannot remove an active write.
    NSString *pattern = [NSTemporaryDirectory() stringByAppendingPathComponent:@"vitrine-motion-XXXXXX"];
    char *path = strdup(pattern.fileSystemRepresentation);
    int descriptor = mkstemp(path);
    if (descriptor >= 0) {
        self.temporary = [NSURL fileURLWithPath:@(path)];
        self.output = [[NSFileHandle alloc] initWithFileDescriptor:descriptor closeOnDealloc:YES];
    }
    free(path);
    if (!self.output) self.rejected = YES;
    completion(self.rejected ? NSURLSessionResponseCancel : NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (self.rejected) return;
    if (data.length > kMaximumClipBytes - self.received) {
        self.rejected = YES;
        [task cancel];
        return;
    }
    self.received += data.length;
    if (self.status != 200) return;
    NSError *error = nil;
    if (![self.output writeData:data error:&error]) {
        SGLog(@"motion: cannot write clip: %@", error.localizedDescription);
        self.rejected = YES;
        [task cancel];
    }
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    NSError *closeError = nil;
    BOOL closed = self.output && [self.output closeAndReturnError:&closeError];
    self.output = nil;
    __block BOOL kept = NO;
    if (!self.rejected && !error && closed && self.status == 200 && self.received > 0) dispatch_sync(storeQueue(), ^{
        if (![NSFileManager.defaultManager createDirectoryAtURL:folder() withIntermediateDirectories:YES attributes:nil error:nil]) return;
        kept = [NSFileManager.defaultManager moveItemAtURL:self.temporary toURL:self.local error:nil];
        if (kept) { handOff(self.local); trim(); }
    });
    if (!kept && self.temporary) {
        NSError *cleanup = nil;
        if (![NSFileManager.defaultManager removeItemAtURL:self.temporary error:&cleanup])
            SGLog(@"motion: cannot remove partial clip: %@", cleanup.localizedDescription);
    }
    BOOL cancelled = [error.domain isEqual:NSURLErrorDomain] && error.code == NSURLErrorCancelled;
    BOOL again = !kept && !self.rejected && !cancelled && self.retries > 0 &&
        (error || self.status == 0 || self.status == 408 || self.status == 429 || self.status >= 500);
    SGLog(@"motion: %@ %@ (%llu bytes, HTTP %ld)%@", self.remote.lastPathComponent, kept ? @"kept" : @"failed",
          (unsigned long long)self.received, (long)self.status, self.rejected ? @", size or write rejected" : @"");
    [session finishTasksAndInvalidate];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (again) { download(self.remote, self.local, self.retries - 1); return; }
        NSArray *waiting = sg_waiting[self.remote];
        [sg_waiting removeObjectForKey:self.remote];
        for (void (^waiter)(NSURL *) in waiting) waiter(kept ? self.local : nil);
    });
}
@end

static void download(NSURL *remote, NSURL *local, NSUInteger retries) {
    SGMotionDownload *owner = [SGMotionDownload new];
    owner.remote = remote;
    owner.local = local;
    owner.retries = retries;
    NSOperationQueue *queue = [NSOperationQueue new];
    queue.maxConcurrentOperationCount = 1;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration
                                                        delegate:owner delegateQueue:queue];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:remote];
    request.allowsConstrainedNetworkAccess = SGFlag(SGKeyMotionLowData, NO);
    [[session dataTaskWithRequest:request] resume];
}

void SGMotionFile(NSURL *remote, void (^done)(NSURL *file)) {
    if (!remote) {
        done(nil);
        return;
    }
    if (!sg_waiting) sg_waiting = [NSMutableDictionary dictionary];
    if (sg_waiting[remote]) {
        [sg_waiting[remote] addObject:[done copy]];
        return;
    }
    sg_waiting[remote] = [NSMutableArray arrayWithObject:[done copy]];
    dispatch_async(storeQueue(), ^{
        NSURL *local = localFor(remote.absoluteString);
        BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:local.path];
        if (exists) handOff(local);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!exists) { download(remote, local, 1); return; }
            NSArray *waiting = sg_waiting[remote];
            [sg_waiting removeObjectForKey:remote];
            for (void (^waiter)(NSURL *) in waiting) waiter(local);
        });
    });
}

void SGMotionPoster(NSURL *file, void (^done)(UIImage *poster)) {
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset assetWithURL:file]];
    generator.appliesPreferredTrackTransform = YES;
    [generator generateCGImageAsynchronouslyForTime:kCMTimeZero completionHandler:^(CGImageRef image, CMTime actual, NSError *error) {
        UIImage *poster = image ? [UIImage imageWithCGImage:image] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ done(poster); });
    }];
}
