// A local file's own cover for where Spotify's player shows its placeholder (LocalFiles.h). The lock
// screen and the queue show the cover of such a file, so it is there to find: first in the image fields
// of the track's metadata, read as a picture or a readable file, then in the system's now playing info,
// taken only while its title and artist agree with the track's, and read again when its artwork changes.
//
// Cache and publication are main-thread only. Metadata files are thumbnailed on a worker once per
// path/playing track, including failures. Only system now-playing misses are retried after a second, and a
// change of the now playing info reads the system artwork again at once and announces a new cover.
#import <MediaPlayer/MediaPlayer.h>
#import "Core/SGCore.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Player/NowPlayingExtras.h"
#import "Shared/Player/PlayerState.h"
#import "LocalFiles.h"

static const NSTimeInterval kRetry = 1;
static const CGFloat kSide = 1200;

NSNotificationName const SGLocalFileFallbackCoverDidChangeNotification = @"SGLocalFileFallbackCoverDidChange";

@interface SGLocalCoverCache : NSObject <SGPlayerStateObserver>
@property(nonatomic, copy) NSString *uri;
@property(nonatomic) NSUInteger generation;
@property(nonatomic, strong) NSMutableDictionary<NSString *, id> *paths;
@property(nonatomic, strong) MPMediaItemArtwork *systemArtwork;
@property(nonatomic, strong) UIImage *systemCover;
@property(nonatomic, strong) NSDate *systemMiss;
@end

@implementation SGLocalCoverCache
- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *uri = SGURIString(state.track.URI);
    if (_uri == uri || [_uri isEqualToString:uri]) return;
    _uri = [uri copy];
    _generation++;
    _paths = [NSMutableDictionary dictionary];
    _systemArtwork = nil;
    _systemCover = nil;
    _systemMiss = nil;
}

// The system's artwork arrives or changes with no layout and no player state change, and the retry interval
// below would hold a miss back: read it again now and announce a new cover, as a metadata thumbnail does.
- (void)nowPlayingInfoChanged:(NSNotification *)note {
    SPTPlayerTrack *track = SGPlayerState().track;
    if (!SGLocalFileIs(SGURIString(track.URI))) return;
    UIImage *before = _systemCover;
    _systemMiss = nil;
    SGLocalFileFallbackCover(track, NULL);
    if (_systemCover != before) [NSNotificationCenter.defaultCenter postNotificationName:SGLocalFileFallbackCoverDidChangeNotification object:_uri];
}
@end

static SGLocalCoverCache *cache(void) {
    static SGLocalCoverCache *kept;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        kept = [SGLocalCoverCache new];
        SGAddPlayerStateObserver(kept);
        // Posted on main (NowPlayingExtras.h).
        [NSNotificationCenter.defaultCenter addObserver:kept selector:@selector(nowPlayingInfoChanged:)
            name:SGNowPlayingInfoDidChangeNotification object:nil];
    });
    [kept playerStateDidChange:SGPlayerState()];
    return kept;
}

// Only local paths and Spotify's local-image URI carry a file to read. In 9.1.90,
// spt_localFileImagePath blindly indexes spotifyURIComponents[2]; NSURL answering
// that selector does not make an arbitrary metadata URL safe to pass to it.
// Decode the known URI here, without entering that unchecked Spotify parser.
static NSString *pathIn(id value) {
    if ([value isKindOfClass:NSString.class] && [value hasPrefix:@"/"]) return value;
    NSURL *url = [value isKindOfClass:NSURL.class] ? value : [value isKindOfClass:NSString.class] ? [NSURL URLWithString:value] : nil;
    if (url.isFileURL) return url.path;
    NSString *prefix = @"spotify:localfileimage:", *address = url.absoluteString;
    if (![address hasPrefix:prefix]) return nil;
    NSString *encoded = [address substringFromIndex:prefix.length];
    // The path is one URI component: any ':' belonging to it must be escaped.
    if (!encoded.length || [encoded containsString:@":"]) return nil;
    NSString *path = encoded.stringByRemovingPercentEncoding;
    return [path hasPrefix:@"/"] ? path : nil;
}

static UIImage *fromMetadata(NSDictionary *metadata, SGLocalCoverCache *kept) {
    for (NSString *field in @[@"image_xlarge_url", @"image_large_url", @"image_url", @"image_small_url"]) {
        id value = metadata[field];
        if ([value isKindOfClass:UIImage.class]) return value;
        NSString *path = pathIn(value);
        if (!path) continue;
        id loaded = kept.paths[path];
        if ([loaded isKindOfClass:UIImage.class]) return loaded;
        if (loaded) continue; // NSNull remembers both pending reads and failed decodes.
        kept.paths[path] = NSNull.null;
        NSString *uri = kept.uri;
        NSUInteger generation = kept.generation;
        static dispatch_queue_t queue;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            queue = dispatch_queue_create("spotifyglass.localFiles.fallback", DISPATCH_QUEUE_SERIAL);
        });
        dispatch_async(queue, ^{
            UIImage *image = SGLocalFileReadCover([NSURL fileURLWithPath:path]);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != kept.generation ||
                    ![uri isEqualToString:SGURIString(SGPlayerState().track.URI)]) return;
                if (!image || SGLocalFileCoverPath(SGLocalFileEditFor(uri))) return;
                kept.paths[path] = image;
                [NSNotificationCenter.defaultCenter postNotificationName:SGLocalFileFallbackCoverDidChangeNotification object:uri];
            });
        });
    }
    return nil;
}

// Case, diacritics and width ignored; a side with no value agrees with anything.
static BOOL agrees(id mine, id theirs) {
    if (![mine isKindOfClass:NSString.class] || ![theirs isKindOfClass:NSString.class] || ![mine length] || ![theirs length]) return YES;
    return [mine compare:theirs options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch] == NSOrderedSame;
}

// System artwork is provisional: the previous local track's artwork can still be in the now playing info
// when the new track agrees by title and artist, so it is read again whenever the info holds another
// MPMediaItemArtwork, and dropped once the info no longer agrees with the track.
static UIImage *fromNowPlaying(SPTPlayerTrack *track, SGLocalCoverCache *kept) {
    NSDictionary *info = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
    MPMediaItemArtwork *artwork = info[MPMediaItemPropertyArtwork];
    if (![artwork isKindOfClass:MPMediaItemArtwork.class] ||
        !agrees(track.trackTitle, info[MPMediaItemPropertyTitle]) || !agrees(track.artistName, info[MPMediaItemPropertyArtist])) {
        kept.systemArtwork = nil;
        kept.systemCover = nil;
        return nil;
    }
    if (artwork == kept.systemArtwork && kept.systemCover) return kept.systemCover;
    UIImage *image = [artwork imageWithSize:CGSizeMake(kSide, kSide)];
    if (!image.CGImage && !image.CIImage) {
        kept.systemArtwork = nil;
        kept.systemCover = nil;
        return nil;
    }
    kept.systemArtwork = artwork;
    kept.systemCover = image;
    return image;
}

UIImage *SGLocalFileFallbackCover(SPTPlayerTrack *track, BOOL *isMetadata) {
    if (isMetadata) *isMetadata = NO;
    NSString *uri = SGURIString(track.URI);
    SGLocalCoverCache *kept = cache();
    // A cover picked in Edit info comes through Spotify's own loader and wins.
    if (!SGLocalFileIs(uri) || ![uri isEqualToString:kept.uri] ||
        SGLocalFileCoverPath(SGLocalFileEditFor(uri))) return nil;
    NSDictionary *metadata = [track.metadata isKindOfClass:NSDictionary.class] ? track.metadata : nil;
    UIImage *image = fromMetadata(metadata, kept);
    if (image) {
        if (isMetadata) *isMetadata = YES;
        return image;
    }
    // A held cover is checked against the info on every call; only a miss waits out the retry interval.
    NSDate *missed = kept.systemMiss;
    if (!kept.systemCover && missed && -missed.timeIntervalSinceNow < kRetry) return nil;
    image = fromNowPlaying(track, kept);
    kept.systemMiss = image ? nil : NSDate.date;
    return image;
}
