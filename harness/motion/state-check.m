// Production follower/catalog with deterministic player and HTTP boundaries. No Spotify or network.
#import <UIKit/UIKit.h>
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/AnimatedArtwork/SGMotionTicket.h"
#import <objc/runtime.h>
#import "player-state.inc"

#define CHECK(value) do { if (!(value)) { fprintf(stderr, "FAIL %d: %s\n", __LINE__, #value); exit(1); } } while (0)

@interface SPTPlayerTrack ()
@property (nonatomic, readwrite) id URI;
@property (nonatomic, readwrite) NSString *artistName;
@property (nonatomic, readwrite) NSDictionary *metadata;
@end
@implementation SPTPlayerTrack
@dynamic artistURI, trackTitle, provider;
@end
@interface SPTPlayerState ()
@property (nonatomic, readwrite) SPTPlayerTrack *track;
@property (nonatomic, readwrite) NSArray *future;
@property (nonatomic, readwrite) id contextURI;
@property (nonatomic, readwrite) SPTPlayerOptions *options;
@property (nonatomic, readwrite) BOOL isPaused, isPlaying, isLoading;
@end
@implementation SPTPlayerState
@dynamic sleepTimer, position, positionAsOfTimestamp;
@dynamic timestamp, playbackSpeed, duration, reverse;
@end

static SPTPlayerState *state;
static __weak id<SGPlayerStateObserver> observer;
static NSURL *walkCanvas;
static NSURL *store;
static NSString *edition = @"first";
static NSDictionary *editorialVideos;
static NSData *redLogo, *blueLogo;
static BOOL blue;

static BOOL advanceAllowed = YES;
BOOL SGOptionalWorkMayRun(BOOL expensive) { return advanceAllowed; }
static NSMutableArray<NSString *> *requested;
static NSMutableDictionary<NSString *, SGMotionTicket *> *tickets;
NSArray *SGMotionSourceOrder(void) { return @[@"canvas", @"applemusic"]; }
CGFloat SGMotionPixels(void) { return 720; }
NSURL *SGMotionCanvasIn(NSDictionary *metadata) {
    NSString *address = metadata[@"canvas.url"];
    return address ? [NSURL URLWithString:address] : nil;
}
SGMotionTicket *SGMotionRequestClip(NSString *uri, NSURL *canvas, NSString *artist, NSString *album,
                     CGFloat pixels, void (^done)(NSURL *, NSString *)) {
    walkCanvas = canvas;
    SGMotionTicket *ticket = [SGMotionTicket new];
    [requested addObject:uri];
    tickets[uri] = ticket;
    done(canvas, canvas ? @"canvas" : nil);
    return ticket;
}
void SGMotionFile(NSURL *remote, void (^done)(NSURL *)) { done(remote); }
SGMotionTicket *SGMotionRequestFile(NSURL *remote, void (^done)(NSURL *)) {
    SGMotionTicket *ticket = [SGMotionTicket new];
    dispatch_async(dispatch_get_main_queue(), ^{ if (!ticket.cancelled) done(remote); });
    return ticket;
}
BOOL SGFlag(NSString *key, BOOL fallback) { return fallback; }
NSURL *SGMotionTestAlbumAnswersFile(void) { return store; }

static void waitFor(BOOL (^ready)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!ready() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    CHECK(ready());
}

@interface CatalogProtocol : NSURLProtocol
@end
@implementation CatalogProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *url = self.request.URL;
        NSData *data;
        if ([url.host isEqual:@"amp-api.music.apple.com"]) {
            NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
            NSMutableDictionary *query = [NSMutableDictionary dictionary];
            for (NSURLQueryItem *item in parts.queryItems) query[item.name] = item.value;
            BOOL artist = [query[@"types"] isEqual:@"artists"];
            NSString *term = query[@"term"];
            NSDictionary *attributes = artist
                ? @{@"name": term, @"editorialArtwork": @{@"musicContentColorLogoTrimmed":
                    @{@"url": @"https://fixture.invalid/logo.png", @"width": @1024, @"height": @1024}}}
                : @{@"name": [term substringFromIndex:@"Artist ".length], @"artistName": @"Artist",
                    @"editorialVideo": editorialVideos ?: @{@"motionTallVideo3x4": @{@"video":
                        [NSString stringWithFormat:@"https://fixture.invalid/%@/%@/master.m3u8", edition,
                            [[term substringFromIndex:@"Artist ".length] stringByReplacingOccurrencesOfString:@" " withString:@"-"]]}}};
            data = [NSJSONSerialization dataWithJSONObject:
                @{@"results": @{artist ? @"artists" : @"albums": @{@"data": @[@{@"attributes": attributes}]}}} options:0 error:nil];
        } else if ([url.path hasSuffix:@"master.m3u8"]) {
            data = [@"#EXTM3U\n#EXT-X-STREAM-INF:RESOLUTION=720x960\nmedia.m3u8" dataUsingEncoding:NSUTF8StringEncoding];
        } else if ([url.path hasSuffix:@"media.m3u8"]) {
            data = [@"#EXTM3U\nclip.mp4" dataUsingEncoding:NSUTF8StringEncoding];
        } else {
            CHECK([url.path isEqual:@"/logo.png"]);
            data = blue ? blueLogo : redLogo;
        }
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:nil];
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [self.client URLProtocol:self didLoadData:data];
        [self.client URLProtocolDidFinishLoading:self];
    });
}
- (void)stopLoading {}
@end

static NSURL *album(NSString *name) {
    __block BOOL finished = NO;
    __block NSURL *value;
    SGMotionAlbumCover(@"Artist", name, 720, ^(NSURL *file) { value = file; finished = YES; });
    waitFor(^BOOL { return finished; });
    return value;
}
static UIImage *logo(NSString *artist) {
    __block BOOL finished = NO;
    __block UIImage *value;
    SGMotionArtistLogo(artist, 1024, ^(UIImage *image) { value = image; finished = YES; });
    waitFor(^BOOL { return finished; });
    return value;
}
static NSData *makeLogo(BOOL red) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1; format.opaque = YES;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1024, 1024) format:format]
        PNGDataWithActions:^(UIGraphicsImageRendererContext *context) {
            [(red ? UIColor.redColor : UIColor.blueColor) setFill];
            UIRectFill(CGRectMake(0, 0, 1024, 1024));
        }];
}
static BOOL isBlue(UIImage *image) {
    CHECK(image.CGImage);
    uint8_t pixel[4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixel, 1, 1, 8, 4, space, kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), image.CGImage);
    CGContextRelease(context); CGColorSpaceRelease(space);
    return pixel[2] > 240 && pixel[0] < 10;
}

int main(void) {
    @autoreleasepool {
        __attribute__((objc_precise_lifetime)) SGMotionFollower *follower = [[SGMotionFollower alloc] initWithBegin:^BOOL(NSString *uri, SPTPlayerState *value) {
            return YES;
        } found:^(NSString *uri, NSURL *file) {}];
        observer = follower;
        requested = [NSMutableArray array];
        tickets = [NSMutableDictionary dictionary];
        state = [SPTPlayerState new];
        state.track = [SPTPlayerTrack new];
        state.track.URI = @"spotify:track:one";
        state.track.metadata = @{};
        publish(state);
        state.track.metadata = @{@"canvas.url": @"https://fixture.invalid/late.mp4"};
        CHECK([observer respondsToSelector:@selector(playerStateDidReport:)]);
        publish(state);
        CHECK([walkCanvas.absoluteString isEqual:@"https://fixture.invalid/late.mp4"]);
        [requested removeAllObjects];
        SPTPlayerTrack *a = [SPTPlayerTrack new]; a.URI = @"spotify:track:a";
        SPTPlayerTrack *b = [SPTPlayerTrack new]; b.URI = @"spotify:track:b";
        state.future = @[a]; publish(state);
        CHECK(([requested isEqual:@[@"spotify:track:a"]]));
        SGMotionTicket *old = tickets[a.URI];
        state.future = @[b]; publish(state);
        CHECK(old.cancelled);
        CHECK(([requested isEqual:@[@"spotify:track:a", @"spotify:track:b"]]));
        publish(state);
        CHECK(requested.count == 2);
        state.future = @[]; publish(state);
        CHECK(tickets[b.URI].cancelled);
        state.future = (id)@[@"invalid"]; publish(state);
        CHECK(requested.count == 2);
        state.future = @[b]; advanceAllowed = NO; publish(state);
        CHECK(requested.count == 2);
        advanceAllowed = YES; state.isPaused = YES; publish(state);
        CHECK(requested.count == 3 && [requested.lastObject isEqual:b.URI]);
        old = tickets[b.URI];
        state.track = b; publish(state);
        CHECK(old.cancelled);
        CHECK(requested.count == 4); // only B's own fetch, not another B ahead
        advanceAllowed = NO;
        state.track = a; state.future = @[b]; publish(state);
        CHECK(requested.count == 5 && [requested.lastObject isEqual:a.URI]);
        (void)follower;

        NSURL *root = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
            URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        CHECK([NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil]);
        store = [root URLByAppendingPathComponent:@"answers.plist"];
        CHECK(([@{@"album\n1\nartist\nexpired": @{@"url": @"https://fixture.invalid/expired.mp4",
            @"at": [NSDate dateWithTimeIntervalSinceNow:-8 * 24 * 3600]},
            @"album\n1\nartist\nsaved": @{@"url": @"https://fixture.invalid/saved.mp4", @"at": NSDate.date}}
            writeToURL:store atomically:YES]));
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSString *tokenKey = @"spotifyglass.motion.token";
        id prior = [defaults objectForKey:tokenKey];
        NSData *claims = [NSJSONSerialization dataWithJSONObject:@{@"exp": @4102444800} options:0 error:nil];
        [defaults setObject:[NSString stringWithFormat:@"e30.%@.test", [claims base64EncodedStringWithOptions:0]] forKey:tokenKey];
        CHECK([NSURLProtocol registerClass:CatalogProtocol.class]);
        CHECK([album(@"Saved").absoluteString isEqual:@"https://fixture.invalid/saved.mp4"]);
        for (NSUInteger i = 0; i < 201; i++) {
            NSString *name = [NSString stringWithFormat:@"Album %lu", (unsigned long)i];
            CHECK(album(name) != nil);
        }
        waitFor(^BOOL {
            return [NSDictionary dictionaryWithContentsOfURL:store][@"album\n1\nartist\nalbum 200"] != nil;
        });
        NSDictionary *saved = [NSDictionary dictionaryWithContentsOfURL:store];
        CHECK(saved.count == 200 && !saved[@"album\n1\nartist\nexpired"] && !saved[@"album\n1\nartist\nalbum 0"]);
        edition = @"second";
        CHECK([album(@"Album 200").absoluteString isEqual:@"https://fixture.invalid/first/Album-200/clip.mp4"]);
        CHECK([album(@"Album 0").absoluteString isEqual:@"https://fixture.invalid/second/Album-0/clip.mp4"]);

        editorialVideos = @{
            @"motionTallVideo3x4": @{@"video": @"https://fixture.invalid/tall/master.m3u8"},
            @"motionDetailTall": @{@"video": @"https://fixture.invalid/detail-tall/master.m3u8"},
            @"motionSquareVideo1x1": @{@"video": @"https://fixture.invalid/square/master.m3u8"},
            @"motionDetailSquare": @{@"video": @"https://fixture.invalid/detail-square/master.m3u8"},
        };
        CHECK([album(@"All formats").absoluteString isEqual:@"https://fixture.invalid/tall/clip.mp4"]);
        editorialVideos = @{
            @"motionDetailTall": @{@"video": @"https://fixture.invalid/detail-tall/master.m3u8"},
            @"motionSquareVideo1x1": @{@"video": @"https://fixture.invalid/square/master.m3u8"},
            @"motionDetailSquare": @{@"video": @"https://fixture.invalid/detail-square/master.m3u8"},
        };
        CHECK([album(@"Detail tall").absoluteString isEqual:@"https://fixture.invalid/detail-tall/clip.mp4"]);
        editorialVideos = @{
            @"motionSquareVideo1x1": @{@"video": @"https://fixture.invalid/square/master.m3u8"},
            @"motionDetailSquare": @{@"video": @"https://fixture.invalid/detail-square/master.m3u8"},
        };
        CHECK([album(@"Square fallback").absoluteString isEqual:@"https://fixture.invalid/square/clip.mp4"]);
        editorialVideos = @{
            @"motionDetailSquare": @{@"video": @"https://fixture.invalid/detail-square/master.m3u8"},
        };
        CHECK([album(@"Detail square fallback").absoluteString isEqual:@"https://fixture.invalid/detail-square/clip.mp4"]);
        editorialVideos = nil;

        redLogo = makeLogo(YES); blueLogo = makeLogo(NO);
        for (NSUInteger i = 0; i < 5; i++)
            CHECK(!isBlue(logo([NSString stringWithFormat:@"Singer %lu", (unsigned long)i])));
        blue = YES;
        CHECK(!isBlue(logo(@"Singer 4")));
        CHECK(isBlue(logo(@"Singer 0"))); // five 4 MiB rasters cannot all remain inside 16 MiB
        [NSURLProtocol unregisterClass:CatalogProtocol.class];
        if (prior) [defaults setObject:prior forKey:tokenKey]; else [defaults removeObjectForKey:tokenKey];
        waitFor(^BOOL {
            return [[NSDictionary dictionaryWithContentsOfURL:store][@"album\n1\nartist\nalbum 0"][@"url"]
                isEqual:@"https://fixture.invalid/second/Album-0/clip.mp4"];
        });
        CHECK([NSFileManager.defaultManager removeItemAtURL:root error:nil]);
        puts("motion state: late Canvas, bounded catalog/album store and logo pixel budget passed");
        return 0;
    }
}
