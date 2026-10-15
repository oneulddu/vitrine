// The song's language in the lyrics' corner menu: which language it is in, told from its lines or set by hand,
// and whether its translation and pronunciation show, kept for every song in that language
// (Shared/Lyrics/Lyrics.h's rules). Main thread only.
#import <UIKit/UIKit.h>
#import "Shared/Lyrics/Lyrics.h"

// The menu for the song: its language as detected or set, the other languages to pick from, and the rule for it.
// `apply` runs after a pick, for the lyrics view to show the song by the rule.
UIMenu *SGRSongLanguageMenu(NSString *trackID, NSArray<SGKaraokeLine *> *lines, void (^apply)(void));
// The language's name in the iPhone's language ("Japanese"), its code when it has none.
NSString *SGRLanguageName(NSString *tag);
