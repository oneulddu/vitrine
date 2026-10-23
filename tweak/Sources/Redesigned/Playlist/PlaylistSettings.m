// The redesign's Playlists page: the cover full screen from the header's picture (PlaylistHeader.x), the curation
// pills closed up (PlaylistRows.x) and Sort and Mix on the ⋯ sheet (PlaylistMenu.x), each on until switched off and
// read at launch.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Playlist.h"

UIViewController *SGRPlaylistSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.playlist.title", @"Playlists") intro:SGRestartNote sections:@[
        SGSection(SGL(@"settings.playlist.cover.header", @"Cover"), @[
            SGSwitchRow(SGL(@"settings.playlist.full_screen_cover.title", @"Full screen cover"),
                        SGL(@"settings.playlist.full_screen_cover.subtitle", @"Tap the picture at the top of a playlist to zoom in or share it"),
                        SGRKeyPlaylistCoverViewer),
        ]),
        SGSection(SGL(@"settings.playlist.hide_on_page.header", @"Hide on a playlist's page"), @[
            SGSwitchRow(SGL(@"settings.playlist.hide.pills.title", @"Curation pills"),
                        SGL(@"settings.playlist.hide.pills.subtitle", @"Add, Mix, Sort and the rest, over the first track"),
                        SGRKeyPlaylistHideCuration),
        ]),
        SGNotedSection(SGL(@"settings.playlist.more_menu.header", @"More menu"), @[
            SGSwitchRow(SGL(@"settings.playlist.sort_mix.title", @"Sort and Mix"),
                        SGL(@"settings.playlist.sort_mix.subtitle", @"At the top of a playlist's ⋯ menu"),
                        SGRKeyPlaylistMenuSortMix),
        ], SGL(@"settings.playlist.sort_mix.note", @"The two curation pills the ⋯ menu does not already offer, so they stay a tap away with the pills hidden.")),
    ] footer:nil];
}
