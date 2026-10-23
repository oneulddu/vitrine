// The redesign's Search page: what the Browse page collapses (SearchSections.x) and the category cards' glass
// (SearchCards.x), each on until switched off and read at launch.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Search.h"

UIViewController *SGRSearchSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.search_tab.title", @"Search") intro:SGRestartNote sections:@[
        SGNotedSection(SGL(@"settings.search_tab.hide.header", @"Hide on Search"), @[
            SGSwitchRow(SGL(@"settings.search_tab.hide.watch_feeds.title", @"Video carousels"),
                        SGL(@"settings.search_tab.hide.watch_feeds.subtitle", @"Playlists you can watch, Explore episodes for you"),
                        SGRKeySearchHideWatchFeeds),
            SGSwitchRow(SGL(@"settings.search_tab.hide.other.title", @"Everything else"),
                        SGL(@"settings.search_tab.hide.other.subtitle", @"Promos and any other section Spotify sends"),
                        SGRKeySearchHideOther),
        ], SGL(@"settings.search_tab.hide.note", @"The category cards always stay.")),
        SGSection(SGL(@"settings.search_tab.cards.header", @"Category cards"), @[
            SGSwitchRow(SGL(@"settings.search_tab.glass_cards.title", @"Tinted glass"),
                        SGL(@"settings.search_tab.glass_cards.subtitle", @"Each card as Liquid Glass in its own color. Off, the cards are Spotify's own."),
                        SGRKeySearchGlassCards),
        ]),
    ] footer:nil];
}
