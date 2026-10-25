// A line of lyrics as a short video for the lock screen's full-screen artwork (LyricsArtwork.x): the
// line, its translation smaller under it when there is one, and the next one dimmed, over the cover blurred
// or over the moving artwork. Core Graphics, Core Text, Core Image
// and AVFoundation only, so harness/lyrics-clip renders the same files on the Mac.
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SGLyricsClipStyle) {
    SGLyricsClipStill = 0,   // one frame, held
    SGLyricsClipAnimated,    // the cover breathes behind the words, in a loop
};

// The 3:4 size of a clip `pixels` wide, both sides a multiple of 16 for the encoder.
CGSize SGLyricsClipSize(CGFloat pixels);
// The lock screen's default background (the cover blurred, 45% darkened), through the shared CPU renderer;
// a dark field for NULL.
// Callers with a preference snapshot use SGLyricsBackgroundCreate directly.
CGImageRef SGLyricsClipBackdrop(CGImageRef cover, CGSize size) CF_RETURNS_RETAINED;
// The clip's first frame, for the lock screen's preview image. `line`, `translation` or `next` may be nil; a
// translation shows smaller under the line, and only with it.
CGImageRef SGLyricsClipFrame(CGImageRef backdrop, NSString *line, NSString *translation, NSString *next, CGSize size) CF_RETURNS_RETAINED;
// Writes the clip as H.264 to `file`, replacing it, and returns once it is written; NO if it was not.
BOOL SGLyricsClipWrite(NSURL *file, CGImageRef backdrop, NSString *line, NSString *translation, NSString *next, CGSize size,
                       SGLyricsClipStyle style);

// The words over moving artwork instead: `motion` is a local video, played from `from` seconds into the
// song, taken round its length, for `seconds`, round its end as often as needed; when the video is no
// longer than that, the whole of it, turned to start there, so the lock screen's loop has no seam. The
// line sung last shows dimmed above the line. Written at the largest 3:4 cut of the video, about its
// middle, at the video's frame rate up to 30 fps. NO for a video stood on its side by its transform, or
// one that does not read. Blocks, so never on the main queue.
BOOL SGLyricsClipWriteOverMotion(NSURL *file, NSURL *motion, NSString *previous, NSString *line, NSString *translation,
                                 NSString *next, double from, double seconds);
// The end of a line's artwork ID, so a clip kept under it is the one wanted: the style, which a clip falling
// back to the cover is drawn in, and with moving artwork m and the first 16 characters of its file's name (the
// store names files by a SHA-1 of their address), so another video for the track redraws the line showing.
NSString *SGLyricsClipLook(NSURL *motion, SGLyricsClipStyle style);
// That clip's first frame, for the preview image, NULL where the clip would not be written.
CGImageRef SGLyricsClipMotionFrame(NSURL *motion, NSString *previous, NSString *line, NSString *translation, NSString *next,
                                   double from) CF_RETURNS_RETAINED;
