// Local files: the tracks Spotify plays from the Files app, under either look. Their URI carries their
// tags, spotify:local:<artist>:<album>:<title>:<seconds>, each part form encoded ("+" for a space), and
// Spotify's core reads them from the file once, when it scans it.
//
//     LocalFiles.m       the URI read back into names, and the edits the user made, kept by the mod
//     LocalFileInfo.x    the edits applied: the player's track metadata, the cover's image request and
//                        the system's now playing artwork
//     EditInfoMenu.x     Edit info in the player's ⋯ menu while a local file plays, and its editor
//     LocalLyrics.h      the user's own .lrc files, linked to a local file or matched by its names
//     LocalCover.m       the file's own cover, found where Spotify's player shows a placeholder
//
// The file itself is never written: Spotify read its tags when it scanned it, and writing them back
// would take a tag writer per format. So an edit is stored by URI and laid over what Spotify read.
//
// Lyrics: Spotify never asks spclient for a local file's lyrics, so the lyrics engine keeps them under
// SGLocalFileLyricsKey and asks the sources by the names here (Shared/Lyrics/KaraokeSource.x).
#import <UIKit/UIKit.h>

// URI -> {title, artist, album, cover (a file name in SGLocalFileCoversDirectory), number}.
#define SGKeyLocalFileEdits @"spotifyglass.localFiles.edits"

// A local file's URI, or a lyrics key made from one.
BOOL SGLocalFileIs(NSString *uri);
// What the lyrics engine keeps a local file under: its URI, and once its names are edited the edit's
// number after a "#", so a rename reads as a new track and its lyrics are looked up again under the new
// names. A new cover alone keeps the key. Posting SGLocalFileEditsDidChangeNotification is what has the
// lyrics engine ask for the new key while the file plays.
// nil for anything but a local file.
NSString *SGLocalFileLyricsKey(NSString *uri);
// The names a local file goes by, the user's edits over its own tags: title, artist, album (each
// present only when not empty) and seconds. Takes a URI or a lyrics key; nil for anything else.
NSDictionary<NSString *, id> *SGLocalFileInfo(NSString *uri);
// The file's own names, as its URI carries them, with no edit over them.
NSDictionary<NSString *, id> *SGLocalFileTags(NSString *uri);

// The user's edit of a local file, nil when there is none. Safe from any thread.
NSDictionary<NSString *, id> *SGLocalFileEditFor(NSString *uri);
// Stores the names (an empty or missing one, or one the file already has, falls back to the file's
// own) and a new cover when `cover` is set; `keepCover` NO drops the stored one. The file's own names
// with no cover remove the edit. Main thread; picker images are already bounded thumbnails.
void SGLocalFileSaveEdit(NSString *uri, NSDictionary<NSString *, NSString *> *names, UIImage *cover, BOOL keepCover);
// Call on main. Loads/decodes the current edited cover off main; completes on main with nil if
// absent, unreadable, or replaced during the read. Consumers must also reject stale track/editor requests.
void SGLocalFileLoadCover(NSString *uri, void (^completion)(UIImage *image));
// Off main: decode an oriented thumbnail directly from a picked file, at the cover's save size.
// Balances security-scoped access; nil for an unreadable/non-image file.
UIImage *SGLocalFileReadCover(NSURL *url);
// Off main for a Photos image without a file URL: bound its size and apply imageOrientation.
UIImage *SGLocalFileThumbnail(UIImage *image);
// Where the stored covers are, and the one an edit names; nil when it names none.
NSString *SGLocalFileCoversDirectory(void);
NSString *SGLocalFileCoverPath(NSDictionary<NSString *, id> *edit);
// A stored cover as the image address Spotify's loader takes for a local file, spotify:localfileimage:
// and the path percent escaped, ":" too, since the loader splits the address on it; and back, nil for
// an address that is not one of these covers.
NSString *SGLocalFileCoverURL(NSString *path);
NSString *SGLocalFileCoverInURL(NSString *url);
// Posted on the main thread after an edit is stored or forgotten, object the URI.
extern NSNotificationName const SGLocalFileEditsDidChangeNotification;

// EditInfoMenu.x: the editor for a local file, presented over `presenter`.
void SGLocalFilePresentEditor(UIViewController *presenter, NSString *uri);

// LocalCover.m: the file's own cover for a local track whose player shows Spotify's placeholder, from the
// image fields of its metadata or the system's now playing artwork; nil for any other track, for one with a
// cover picked in Edit info, and until one is found. Main thread. Optional isMetadata distinguishes
// an authoritative metadata cover from provisional system now-playing artwork (or no image).
@class SPTPlayerTrack;
UIImage *SGLocalFileFallbackCover(SPTPlayerTrack *track, BOOL *isMetadata);
// Main-thread notification after a metadata file's thumbnail becomes available; object is its URI.
extern NSNotificationName const SGLocalFileFallbackCoverDidChangeNotification;
