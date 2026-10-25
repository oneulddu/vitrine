// Regression for Spotify 9.1.90's unchecked local-image URI parser. Exercise the
// actual fallback resolver with unrelated URLs, malformed URIs and valid covers.
#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>
#import "Headers/SPTPlayer.h"
#import "Shared/LocalFiles/LocalFiles.h"

#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #c); exit(1); } } while (0)

static NSUInteger legacyCalls, sequence;
@interface NSURL (SGCrashFixture)
- (NSString *)spt_localFileImagePath;
@end
@implementation NSURL (SGCrashFixture)
- (NSString *)spt_localFileImagePath {
    legacyCalls++;
    NSArray *parts = [self.absoluteString componentsSeparatedByString:@":"];
    return [parts[2] stringByRemovingPercentEncoding];
}
@end

@interface SGTestLocalTrack : NSObject
@property(nonatomic, strong) NSURL *URI;
@property(nonatomic, copy) NSDictionary *metadata;
@property(nonatomic, copy) NSString *trackTitle, *artistName;
@end
@implementation SGTestLocalTrack @end
@interface SGTestNowPlaying : NSObject
@property(nonatomic, copy) NSDictionary *nowPlayingInfo;
@end
@implementation SGTestNowPlaying @end

NSString *SGURIString(id uri) {
    return [uri isKindOfClass:NSURL.class] ? [uri absoluteString] : uri;
}
static SGTestLocalTrack *track(NSDictionary *metadata) {
    SGTestLocalTrack *t = [SGTestLocalTrack new];
    t.URI = [NSURL URLWithString:[NSString stringWithFormat:@"spotify:local:Fixture:Album:Track%lu:60", (unsigned long)++sequence]];
    t.metadata = metadata; t.trackTitle = @"Cover fixture"; t.artistName = @"Fixture artist";
    return t;
}
static UIImage *resolve(SGTestLocalTrack *t) {
    return SGLocalFileFallbackCover((SPTPlayerTrack *)t);
}
int main(void) { @autoreleasepool {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyLocalFileEdits];
    SGTestNowPlaying *center = [SGTestNowPlaying new];
    Method getter = class_getClassMethod(MPNowPlayingInfoCenter.class, @selector(defaultCenter));
    IMP replacement = imp_implementationWithBlock(^id(id self) { return center; });
    IMP original = method_setImplementation(getter, replacement);
    @try {
        for (id address in @[@"cover.jpg", @"https://example.invalid/cover.jpg",
                [NSURL URLWithString:@"https://example.invalid/cover.jpg"],
                @"spotify:image:abc", @"spotify:localfileimage", @"spotify:localfileimage:",
                @"spotify:localfileimage:relative.jpg", @"spotify:localfileimage:/tmp/a:b.jpg",
                @42, NSNull.null]) {
            CHECK(!resolve(track(@{@"image_xlarge_url": address})));
        }
        UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(4, 4)]
            imageWithActions:^(UIGraphicsImageRendererContext *context) {
                [UIColor.redColor setFill]; UIRectFill(CGRectMake(0, 0, 4, 4));
            }];
        NSString *file = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@" local cover: artwork.png"]];
        CHECK([UIImagePNGRepresentation(image) writeToFile:file atomically:YES]);
        for (id address in @[file, [NSURL fileURLWithPath:file], SGLocalFileCoverURL(file),
                [NSURL URLWithString:SGLocalFileCoverURL(file)], image]) {
            CHECK(resolve(track(@{@"image_xlarge_url": address})).CGImage);
        }
        CHECK(resolve(track(@{@"image_xlarge_url": @"cover.jpg", @"image_small_url": file})).CGImage);
        SGTestLocalTrack *fallback = track(@{@"image_url": @"cover.jpg"});
        center.nowPlayingInfo = @{MPMediaItemPropertyTitle: fallback.trackTitle,
            MPMediaItemPropertyArtist: fallback.artistName,
            MPMediaItemPropertyArtwork: [[MPMediaItemArtwork alloc] initWithBoundsSize:image.size
                requestHandler:^UIImage *(CGSize size) { return image; }]};
        CHECK(resolve(fallback).CGImage);
        center.nowPlayingInfo = nil;
        SGTestLocalTrack *edited = track(@{@"image_url": @"cover.jpg"});
        SGLocalFileSaveEdit(edited.URI.absoluteString, @{}, image, YES);
        CHECK(!resolve(edited));
        SGLocalFileSaveEdit(edited.URI.absoluteString, @{}, nil, NO);
        SGTestLocalTrack *remote = track(@{@"image_url": @"cover.jpg"});
        remote.URI = [NSURL URLWithString:@"spotify:track:4uLU6hMCjMI75M1A2tKUQC"];
        CHECK(!resolve(remote));
        CHECK(legacyCalls == 0);
        [NSFileManager.defaultManager removeItemAtPath:file error:nil];
        puts("PASS: local covers; malformed/unrelated URLs, paths, file URLs, escaped Spotify URIs, next-field/system fallback, edited covers; no unsafe Spotify parser calls");
    } @catch (NSException *exception) {
        fprintf(stderr, "FAIL: local cover resolver raised %s: %s\n", exception.name.UTF8String, exception.reason.UTF8String);
        return 1;
    } @finally {
        method_setImplementation(getter, original);
        imp_removeBlock(replacement);
    }
    return 0;
} }
