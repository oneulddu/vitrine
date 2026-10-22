// Every song's lyric-free fallback uses the same selected backdrop and encoder as lyric clips.
#import "SGFluidClip.h"
#import "Shared/LockScreenLyrics/SGLyricsClip.h"

CGImageRef SGFluidClipFrame(CGImageRef cover, CGSize size) {
    if (!cover) return NULL;
    return SGLyricsClipFrame(cover, nil, nil, nil, size);
}

BOOL SGFluidClipWrite(NSURL *file, CGImageRef cover, CGSize size) {
    if (!cover) return NO;
    return SGLyricsClipWrite(file, cover, nil, nil, nil, size, SGLyricsClipAnimated);
}
