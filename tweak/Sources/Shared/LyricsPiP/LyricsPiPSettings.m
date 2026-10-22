#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "LyricsPiP.h"
#import "LyricsPiPBackground.h"
#import "Shared/LyricsBackground/LyricsBackgroundSettings.h"

SGModRow *SGLyricsPiPRow(void) {
    SGModRow *row = SGPageRow(SGL(@"settings.lyrics.pip.title", @"Picture in Picture lyrics"), ^UIViewController *{
        SGModRow *enabled = SGOptionRow(SGL(@"settings.lyrics.pip.title", @"Picture in Picture lyrics"),
            SGL(@"settings.lyrics.pip.subtitle", @"Show lyrics over other apps from the lyrics screen. Restart Spotify after changing this."),
            SGKeyLyricsPiP);
        return [[SGModPage alloc] initWithTitle:SGL(@"settings.lyrics.pip.title", @"Picture in Picture lyrics")
            intro:nil sections:@[SGSection(nil, @[enabled]),
                SGSection(nil, SGLyricsBackgroundRows(SGKeyLyricsPiPBackground))] footer:nil];
    });
    row.subtitle = SGL(@"settings.lyrics.pip.page.subtitle", @"Open lyrics over other apps and customize their background.");
    return row;
}
