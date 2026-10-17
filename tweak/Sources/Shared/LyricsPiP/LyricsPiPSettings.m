#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "LyricsPiP.h"

SGModRow *SGLyricsPiPRow(void) {
    return SGOptionRow(SGL(@"settings.lyrics.pip.title", @"Picture in Picture lyrics"),
                       SGL(@"settings.lyrics.pip.subtitle", @"Show lyrics over other apps from the lyrics screen. Restart Spotify after changing this."),
                       SGKeyLyricsPiP);
}
