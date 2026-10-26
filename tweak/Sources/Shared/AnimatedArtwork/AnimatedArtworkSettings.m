// What the lock screen fills the screen with, the lyrics' style and whether the downloads run in Low Data
// Mode. iOS 26 and up only.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "AnimatedArtwork.h"
#import "Shared/LyricsBackground/LyricsBackgroundSettings.h"

SGLockArtwork SGLockScreenArtwork(void) {
    if (@available(iOS 26.0, *)) {
        // The old switch's YES and NO read as Moving artwork and Off, the enum's first two.
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGMigrateKey(SGKeyLockScreenMotion, SGKeyLockScreenArtwork); });
        return (SGLockArtwork)SGInt(SGKeyLockScreenArtwork, SGLockArtworkOff);
    }
    return SGLockArtworkOff;
}

NSArray *SGLockScreenMotionRows(void) {
    if (@available(iOS 26.0, *)) {
        SGLockScreenArtwork();   // moves the old switch over before the row reads the new key
        SGModRow *style = SGChoiceRow(SGL(@"settings.lockscreen.lyrics_style.title", @"Lyrics style"), SGL(@"settings.lockscreen.lyrics_style.subtitle", @"Still draws each line once; Animated gently moves the selected background. Applies when moving artwork is unavailable."),
                                      SGKeyLockScreenLyricsStyle, @[SGL(@"settings.lockscreen.lyrics_style.choice.still", @"Still"), SGL(@"settings.lockscreen.lyrics_style.choice.animated", @"Animated")], 0);
        style.visible = ^BOOL { return SGLockArtworkShowsLyrics(SGLockScreenArtwork()); };
        SGModRow *layout = SGChoiceRow(SGL(@"settings.lockscreen.lyrics_layout.title", @"Layout"), SGL(@"settings.lockscreen.lyrics_layout.subtitle", @"Where the lyrics sit. Poster shows the line alone, larger."),
                                       SGKeyLockScreenLyricsLayout, @[SGL(@"settings.lockscreen.lyrics_layout.choice.left", @"Left"), SGL(@"settings.lockscreen.lyrics_layout.choice.centered", @"Centered"), SGL(@"settings.lockscreen.lyrics_layout.choice.poster", @"Poster")], 0);
        layout.visible = style.visible;
        SGModRow *translation = SGOptionRow(SGL(@"settings.lockscreen.translations.title", @"Translations"), SGL(@"settings.lockscreen.translations.subtitle", @"Under the line, when the lyrics have one or automatic translation makes one"), SGKeyLockScreenTranslation);
        translation.visible = style.visible;
        SGModRow *lowData = SGOptionRow(SGL(@"settings.lockscreen.low_data.title", @"Download in Low Data Mode"), SGL(@"settings.lockscreen.low_data.subtitle", @"Moving artwork, up to about 7 MB a song. Applies to animated artwork throughout Vitrine."), SGKeyMotionLowData);
        lowData.visible = ^BOOL {
            SGLockArtwork artwork = SGLockScreenArtwork();
            return artwork == SGLockArtworkMotion || artwork == SGLockArtworkEverySong || artwork == SGLockArtworkMotionLyrics;
        };
        SGModRow *sources = SGMotionSourcesRow();
        sources.visible = lowData.visible;
        SGModRow *star = SGOptionRow(SGL(@"settings.lockscreen.star_switch.title", @"Switch with the star"), SGL(@"settings.lockscreen.star_switch.subtitle", @"The lock screen widget's star swaps the moving artwork for the lyrics "
                                                             @"and back. It takes the place of Spotify's like and dislike buttons"),
                                     SGKeyLockScreenStar);
        star.visible = ^BOOL { return SGLockScreenArtwork() != SGLockArtworkOff; };
        SGModRow *artwork = SGChoiceRow(SGL(@"settings.lockscreen.artwork.title", @"Full-screen artwork"), nil,
                        SGKeyLockScreenArtwork, @[SGL(@"common.off", @"Off"), SGL(@"settings.lockscreen.artwork.choice.moving", @"Moving artwork"), SGL(@"settings.lockscreen.artwork.choice.lyrics", @"Lyrics"), SGL(@"settings.lockscreen.artwork.choice.every_song", @"Every song"), SGL(@"settings.lockscreen.artwork.choice.moving_with_lyrics", @"Moving artwork with lyrics")],
                        SGLockArtworkOff);
        artwork.choiceNotes = @[
            SGL(@"settings.lockscreen.artwork.note.off", @"Leaves Spotify's artwork unchanged."),
            SGL(@"settings.lockscreen.artwork.note.moving", @"The Canvas or Apple Music's animated cover."),
            SGL(@"settings.lockscreen.artwork.note.lyrics", @"Lyrics, a line at a time."),
            SGL(@"settings.lockscreen.artwork.note.every_song", @"Uses moving artwork when available; otherwise uses your selected background."),
            SGL(@"settings.lockscreen.artwork.subtitle", @"Puts the lyrics over the Canvas or animated cover."),
        ];
        NSMutableArray *rows = [@[
            artwork,
            style,
            layout,
            translation,
            star,
            sources,
            lowData,
        ] mutableCopy];
        NSArray<SGModRow *> *background = SGLyricsBackgroundRows(@"spotifyglass.lockscreen.background");
        background.firstObject.subtitle = SGL(@"settings.background.mode.subtitle", @"Used when moving artwork is unavailable.");
        for (SGModRow *row in background) {
            BOOL (^visible)(void) = row.visible;
            row.visible = ^BOOL {
                SGLockArtwork picked = SGLockScreenArtwork();
                return (picked == SGLockArtworkEverySong || SGLockArtworkShowsLyrics(picked)) && (!visible || visible());
            };
        }
        [rows insertObjects:background atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(3, background.count)]];
        return rows;
    }
    return @[SGLockScreenArtworkNeedsRow()];
}

// Below iOS 26 the section stays, with one row that says why there is nothing to pick.
SGModRow *SGLockScreenArtworkNeedsRow(void) {
    return SGStatActionRow(SGL(@"settings.lockscreen.artwork.row.title", @"Full-screen artwork"), nil, ^NSString *{ return SGL(@"settings.lockscreen.needs_ios26.status", @"Needs iOS 26"); }, ^{
        NSString *message = [NSString stringWithFormat:SGL(@"settings.lockscreen.needs_ios26.alert.message", @"This iPhone has iOS %@. The lock screen takes moving artwork "
                                                       @"from apps from iOS 26 on, so the Canvas and Apple Music's animated "
                                                       @"covers can show there once the iPhone is updated."), UIDevice.currentDevice.systemVersion];
        SGPresentInformation(SGTopController(), SGL(@"settings.lockscreen.needs_ios26.alert.title", @"Needs iOS 26"), message);
    });
}
