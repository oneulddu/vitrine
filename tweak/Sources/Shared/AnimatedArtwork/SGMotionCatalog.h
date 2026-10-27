// Catalog metadata shares the motion client's token, requests and bounded caches.
#import <UIKit/UIKit.h>

// Main queue. Only an unambiguous, exact artist AND edition match supplies notes.
// The dictionary contains plain-text "short" and "standard", or is nil.
// Edition evidence keys: trackCount, releaseYear, explicit (NSNumber, absent
// when unknown). Count, year and the page-established explicit flag are all
// required and must agree. Unknown rating never authorizes a note.
void SGMotionAlbumNotes(NSString *artist, NSString *album, NSDictionary *edition, void (^done)(NSDictionary *notes));
NSString *SGMotionEditorialText(id html);
NSDictionary *SGMotionAlbumNotesIn(NSArray *records, NSString *artist, NSString *album, NSDictionary *edition);

// Artist records include their albums. At least two distinct release titles must
// agree, and only one namesake may agree. No evidence means no replacement.
NSDictionary *SGMotionArtistMatch(NSArray *records, NSString *artist, NSArray<NSString *> *titles);
typedef NS_ENUM(NSUInteger, SGMotionArtistArtworkOutcome) {
    SGMotionArtistArtworkFinished,
    SGMotionArtistArtworkNeedsEvidence,
    SGMotionArtistArtworkMetadataFailed,
};
void SGMotionArtistArtwork(NSString *artist, NSArray<NSString *> *titles, CGFloat pixels,
                          BOOL photo, BOOL motion, void (^done)(UIImage *photo, NSURL *file, SGMotionArtistArtworkOutcome outcome));
// New release rows may re-evaluate a NeedsEvidence result. Metadata failures are
// not cached: a new page can retry them. Finished includes failed asset attempts.
