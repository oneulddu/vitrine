// Album redesign: where each track's plays show (Album.h), read from the choice on the Albums page or, until one
// is stored, from the switch it replaced, which stays where it was.
#import "Core/SGPrefs.h"
#import "Album.h"

BOOL SGRAlbumUsesSpotifyCounts(void) {
    return SGInt(SGRKeyAlbumPlayCountsSource, 0) == 1;
}

SGRAlbumPlayCountsPlace SGRAlbumPlayCountsWhere(void) {
    NSInteger place = SGInt(SGRKeyAlbumPlayCountsPlace, -1);
    if (place >= SGRAlbumPlayCountsOff && place <= SGRAlbumPlayCountsInMenu) return (SGRAlbumPlayCountsPlace)place;
    return SGEnabled(SGRKeyAlbumPlayCounts) ? SGRAlbumPlayCountsInRow : SGRAlbumPlayCountsOff;
}
