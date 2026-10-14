#import "Core/SGLocalize.h"
#import "Settings/SGModPage.h"
#import "Playlist.h"

UIViewController *SGPlaylistSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.playlist.title", @"Playlists") intro:nil sections:@[
        SGSection(SGL(@"settings.playlist.header", @"Header"), @[
            SGOptionRow(SGL(@"settings.playlist.artwork_background.title", @"Artwork background"), nil, SGKeyPlaylistBackdrop),
        ]),
        SGSection(SGL(@"settings.playlist.hide_in_header.header", @"Hide in the playlist header"), @[
            SGHideRow(SGL(@"settings.playlist.hide.artwork.title", @"Cover artwork"), nil, SGHidePlaylistArtwork),
            SGHideRow(SGL(@"settings.playlist.hide.description.title", @"Description"), nil, SGHidePlaylistDescription),
            SGHideRow(SGL(@"settings.playlist.hide.creator.title", @"Creator and collaborators"), nil, SGHidePlaylistCreator),
            SGHideRow(SGL(@"settings.playlist.hide.length.title", @"Length and saves"), nil, SGHidePlaylistLength),
        ]),
        SGSection(SGL(@"settings.playlist.hide_buttons.header", @"Hide playlist buttons"), @[
            SGHideRow(SGL(@"settings.playlist.hide.video.title", @"Video"), nil, SGHidePlaylistVideo),
            SGHideRow(SGL(@"settings.playlist.hide.add_to_library.title", @"Add to library"), nil, SGHidePlaylistAddTo),
            SGHideRow(SGL(@"settings.playlist.hide.download.title", @"Download"), nil, SGHidePlaylistDownload),
            SGHideRow(SGL(@"settings.playlist.hide.share.title", @"Share"), nil, SGHidePlaylistShare),
            SGHideRow(SGL(@"settings.playlist.hide.more.title", @"More"), nil, SGHidePlaylistMore),
        ]),
        SGSection(SGL(@"settings.playlist.hide_above_tracks.header", @"Hide above the tracks"), @[
            SGHideRow(SGL(@"settings.playlist.hide.pills.title", @"Curation pills"), nil, SGHidePlaylistPills),
            SGHideRow(SGL(@"settings.playlist.hide.find_bar.title", @"Find and sort bar"), nil, SGHidePlaylistFind),
        ]),
    ] footer:nil];
}
