// Native cover ownership: metadata may upgrade our provisional system artwork, but never Spotify's.
// Kept here so the resolver harness exercises the same image-view publication as the native hooks.
#import <objc/runtime.h>
#import "Shared/LocalFiles/LocalFiles.h"
#import "Shared/Player/PlayerState.h"

static inline void SGLocalCoverFill(UIImageView *view) {
    static char imageKey, trackKey, metadataKey;
    if (!view) return;
    BOOL ours = view.image && view.image == objc_getAssociatedObject(view, &imageKey);
    if (view.image && !ours) return;
    SPTPlayerTrack *track = SGPlayerState().track;
    NSString *uri = SGURIString(track.URI);
    BOOL sameTrack = ours && [uri isEqualToString:objc_getAssociatedObject(view, &trackKey)];
    if (sameTrack && [objc_getAssociatedObject(view, &metadataKey) boolValue]) return;
    BOOL isMetadata = NO;
    UIImage *cover = SGLocalFileFallbackCover(track, &isMetadata);
    if (!cover && (!ours || sameTrack)) return;
    view.image = cover;
    objc_setAssociatedObject(view, &imageKey, cover, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &trackKey, uri, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(view, &metadataKey, @(isMetadata), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
