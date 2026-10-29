#import <Foundation/Foundation.h>
@class SGKaraokeLine;
static const NSUInteger SGLyricsLanguageCacheSongLimit = 128;

// Capture on the model's owner queue. The returned lines/words are private copies for read-only analysis.
NSArray<SGKaraokeLine *> *SGLyricsLanguageSnapshot(NSArray<SGKaraokeLine *> *lines);
