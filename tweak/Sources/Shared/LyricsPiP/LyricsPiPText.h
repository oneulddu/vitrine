// Which text a lyrics PiP frame shows, decided apart from the view so it can be checked offline.
// Pure: lines and a position in, text out; no player, settings or rendering.
#import <Foundation/Foundation.h>
#import "Shared/Lyrics/Lyrics.h"

typedef NS_ENUM(NSInteger, SGLyricsPiPTextKind) {
    SGLyricsPiPTextNoLyrics,     // lines == nil
    SGLyricsPiPTextInstrumental, // empty lines, or a gap / finished word-timed line / empty or ♪ line
    SGLyricsPiPTextUntimed,      // lines exist but are not synced
    SGLyricsPiPTextLine,         // a sung line
};

// current/next are never nil on return (use @"" when there is nothing). For Untimed, current is the
// first line's text and next is @""; for Instrumental only next carries anything to show. The caller
// supplies the localized strings for NoLyrics, Instrumental and Untimed.
SGLyricsPiPTextKind SGLyricsPiPTextFor(NSArray<SGKaraokeLine *> *lines, NSInteger positionMs,
                                       NSString **current, NSString **next);
// The exact selected source line, or nil during a break/no lyrics. No fetches or side effects.
SGKaraokeLine *SGLyricsPiPSelectedLine(NSArray<SGKaraokeLine *> *lines, NSInteger positionMs);
