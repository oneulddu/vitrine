// What the lock screen fills the screen with, the lyrics' style and whether the downloads run in Low Data
// Mode. iOS 26 and up only.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "AnimatedArtwork.h"

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
        SGModRow *style = SGChoiceRow(SGL(@"settings.lockscreen.lyrics_style.title", @"Lyrics style"), SGL(@"settings.lockscreen.lyrics_style.subtitle", @"Still draws each line once; Animated breathes the cover behind it. "
                                                       @"With moving artwork, for songs that have none"),
                                      SGKeyLockScreenLyricsStyle, @[SGL(@"settings.lockscreen.lyrics_style.choice.still", @"Still"), SGL(@"settings.lockscreen.lyrics_style.choice.animated", @"Animated")], 0);
        style.visible = ^BOOL { return SGLockArtworkShowsLyrics(SGLockScreenArtwork()); };
        SGModRow *lowData = SGOptionRow(SGL(@"settings.lockscreen.low_data.title", @"Download in Low Data Mode"), SGL(@"settings.lockscreen.low_data.subtitle", @"Moving artwork, up to about 7 MB a song"), SGKeyMotionLowData);
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
        return @[
            SGChoiceRow(SGL(@"settings.lockscreen.artwork.title", @"Full-screen artwork"), SGL(@"settings.lockscreen.artwork.subtitle", @"The Canvas or Apple Music's animated cover, or the lyrics a line at a time. "
                                                 @"Every song puts the cover over a moving blur of it where a song has neither. "
                                                 @"Moving artwork with lyrics puts the lines over the Canvas or animated cover"),
                        SGKeyLockScreenArtwork, @[SGL(@"common.off", @"Off"), SGL(@"settings.lockscreen.artwork.choice.moving", @"Moving artwork"), SGL(@"settings.lockscreen.artwork.choice.lyrics", @"Lyrics"), SGL(@"settings.lockscreen.artwork.choice.every_song", @"Every song"), SGL(@"settings.lockscreen.artwork.choice.moving_with_lyrics", @"Moving artwork with lyrics")],
                        SGLockArtworkOff),
            style,
            star,
            sources,
            lowData,
        ];
    }
    return @[SGLockScreenArtworkNeedsRow()];
}

// Below iOS 26 the section stays, with one row that says why there is nothing to pick.
SGModRow *SGLockScreenArtworkNeedsRow(void) {
    return SGStatActionRow(SGL(@"settings.lockscreen.artwork.row.title", @"Full-screen artwork"), nil, ^NSString *{ return SGL(@"settings.lockscreen.needs_ios26.status", @"Needs iOS 26"); }, ^{
        NSString *message = [NSString stringWithFormat:SGL(@"settings.lockscreen.needs_ios26.alert.message", @"This iPhone has iOS %@. The lock screen takes moving artwork "
                                                       @"from apps from iOS 26 on, so the Canvas and Apple Music's animated "
                                                       @"covers can show there once the iPhone is updated."), UIDevice.currentDevice.systemVersion];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.lockscreen.needs_ios26.alert.title", @"Needs iOS 26") message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.ok", @"OK") style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
}
