// The Lyrics page's parts; App/Pages.m assembles the page.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Lyrics.h"
#import "Shared/LocalFiles/LocalLyrics.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"

SGModSection *SGLyricsSourcesSection(BOOL namingSource) {
    SGModRow *sources = SGPageRow(SGL(@"settings.lyrics.sources.row.title", @"Sources"), ^UIViewController *{ return SGLyricsSourcesPage(); });
    sources.value = ^NSString *{
        // The first one asked and how many follow it, short enough to sit beside the title.
        NSArray<NSString *> *order = SGLyricsOrder();
        if (!order.count) return SGL(@"common.off", @"Off");
        NSString *first = SGLyricsProviderFor(order.firstObject).name;
        return order.count == 1 ? first : [NSString stringWithFormat:SGL(@"settings.lyrics.sources.summary.format", @"%@ +%lu"), first, (unsigned long)order.count - 1];
    };
    SGModRow *imported = SGPageRow(SGL(@"settings.lyrics.imported_lrc.title", @"Imported LRC files"), ^UIViewController *{ return SGImportedLRCPage(); });
    imported.value = ^NSString *{
        NSUInteger count = SGImportedLRCFiles().count;
        return count ? @(count).stringValue : SGL(@"settings.lyrics.imported_lrc.value.none", @"None");
    };
    NSMutableArray<SGModRow *> *rows = [NSMutableArray arrayWithObjects:sources, imported,
        SGSwitchRow(SGL(@"settings.lyrics.all_tracks.title", @"Lyrics for every track"), SGL(@"settings.lyrics.all_tracks.subtitle", @"Even where Spotify has none"), SGKeyLyricsAllTracks), SGSpicyLyricsKeyRow(), SGDeezerARLRow(), nil];
    // Spicy Lyrics' terms ask for its credit wherever its lines show (Shared/LyricsSources/SpicyLyrics.m), so the switch
    // says so, or its credit under the lyrics reads as the switch not working (issue #20).
    if (namingSource) [rows addObject:SGOptionRow(SGL(@"settings.lyrics.show_source.title", @"Show source"), SGL(@"settings.lyrics.show_source.subtitle", @"Spicy Lyrics is always credited after the last line: its terms ask for it"), SGKeyLyricsCredit)];
    if (SGEeveeLyricsOn()) {
        [rows addObject:SGOptionRow(SGL(@"settings.lyrics.use_beside_eevee.title", @"Use these sources anyway"), SGL(@"settings.lyrics.use_beside_eevee.subtitle", @"Only if EeveeSpotify's lyrics are really off"), SGKeyLyricsBesideEevee)];
        return SGNotedSection(SGL(@"settings.lyrics.sources.header", @"Sources"), rows, SGL(@"settings.lyrics.sources.eevee_conflict.footer", @"EeveeSpotify's lyrics are on, so it answers Spotify's lyrics and these sources stay "
                                                @"off: both answering froze Spotify after launch. Turn its lyrics off in its own "
                                                @"settings to use these."));
    }
    return SGSection(SGL(@"settings.lyrics.sources.header", @"Sources"), rows);
}

SGModRow *SGLockScreenLyricsRow(void) {
    return SGOptionRow(SGL(@"settings.lyrics.lockscreen_lyrics.title", @"Lock screen lyrics"), SGL(@"settings.lyrics.lockscreen_lyrics.subtitle", @"Current line in place of the artist"), SGKeyLockScreenLyrics);
}

SGModRow *SGLyricsTranslationLanguageRow(void) {
    SGModRow *row = SGChoiceRow(SGL(@"settings.lyrics.translation_language.title", @"Translation language"), nil, SGKeyLyricsTranslationLanguage, SGLyricsTranslationLanguageNames(), 0);
    row.choiceFooter = SGL(@"settings.lyrics.translation_language.footer", @"A language brings Musixmatch's community translations to lyrics that have none, "
                       @"which sends Musixmatch each song's ID. Any shows the first translation the lyrics come with. "
                       @"It is also the language the lyrics' translate menu translates into, offered only for songs in another one; "
                       @"with Any, the iPhone's own language.");
    return row;
}

// Only the redesign's lyrics view draws it, and every one there is redrawn as the switch flips.
SGModRow *SGLyricsRomanisedRow(void) {
    SGModRow *row = SGOptionRow(SGL(@"settings.lyrics.romanized.title", @"Romanized lyrics"), SGL(@"settings.lyrics.romanized.subtitle", @"Lines in other alphabets, again in Latin letters"), SGKeyLyricsRomanised);
    row.changed = ^(BOOL on) {
        [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsRomanisedDidChangeNotification object:nil];
    };
    return row;
}

SGModRow *SGLyricsJapaneseReadingRow(void) {
    NSArray<NSString *> *choices = @[SGL(@"settings.lyrics.japanese_reading.romaji", @"Romaji"),
                                    SGL(@"settings.lyrics.japanese_reading.hiragana", @"Hiragana")];
    SGModRow *row = SGMenuRow(SGL(@"settings.lyrics.japanese_reading.title", @"Japanese reading"), choices,
                             ^NSString *{ return choices[SGFlag(SGKeyLyricsJapaneseKana, NO) ? 1 : 0]; }, ^(NSInteger index) {
        SGSetEnabled(SGKeyLyricsJapaneseKana, index == 1);
        [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsRomanisedDidChangeNotification object:nil];
    });
    row.waitsOn = SGKeyLyricsRomanised;
    return row;
}

// Only the redesign's lyrics view sweeps words.
SGModRow *SGLyricsWordTimingRow(void) {
    return SGOptionRow(SGL(@"settings.lyrics.simulate_word_timing.title", @"Simulate word timing"), nil, SGKeyLyricsSimulateWords);
}

// Read wherever lines are timed, so it applies as the thumb moves.
SGModRow *SGLyricsDelayRow(void) {
    return SGSliderRow(SGL(@"settings.lyrics.delay.title", @"Delay"), nil, 0, 1000, 25, ^double { return SGInt(SGKeyLyricsDelay, 0); },
                       ^(double value) { SGSetInt(SGKeyLyricsDelay, lround(value)); },
                       ^NSString *(double value) { return [NSString stringWithFormat:SGL(@"settings.lyrics.delay.format", @"%ld ms"), lround(value)]; });
}
