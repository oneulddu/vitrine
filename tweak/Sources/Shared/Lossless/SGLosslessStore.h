#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Documents/Lossless: FLAC and ALAC files, put there by the user or downloaded. A file goes with the Spotify track
// it was proven against (SGLosslessStoreRemember); until then a file is a candidate when its title tag (or its
// name) is the track's title and its length is within 2 s of the track's. Artists are not compared: a tag can
// name the composer where Spotify names the performer.
// All store I/O runs on the coordinator's serial store queue, never main.
NSString *SGLosslessStoreDirectory(void);
// The file for the track, or nil.
NSString *_Nullable SGLosslessStoreFile(NSString *uri, NSString *title, double duration);
// Whether a file is there for a track whose length is not known yet (an upcoming one): by the
// index, else by title alone.
BOOL SGLosslessStoreHas(NSString *uri, NSString *title);
// The file matched the track's sound: look it up by the track from now on.
void SGLosslessStoreRemember(NSString *uri, NSString *path);
NS_ASSUME_NONNULL_END
