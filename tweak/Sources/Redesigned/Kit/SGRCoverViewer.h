// The Kit's full screen cover: a page's picture over whatever is on top, black, fitted to the screen, pinched or
// double tapped to zoom, and dragged down or closed to go; Share hands it to the system's share sheet, which saves it
// to Photos too. The album's header and the playlist's open it from their picture (Album/AlbumHeader.x,
// Playlist/PlaylistHeader.x).
// Threading: main thread only.
#import <UIKit/UIKit.h>

// `image` full screen, dark; `accessibilityName` is what VoiceOver calls the picture ("Album cover"). nil is a no-op.
void SGRShowCover(UIImage *image, NSString *accessibilityName);
