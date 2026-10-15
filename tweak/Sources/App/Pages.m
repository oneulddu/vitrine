#import "Core/SGCore.h"
#import "Shared/AppIcon/AppIcon.h"
#import "Shared/AudioEffects/AudioEffectsPage.h"
#import "Shared/Fonts/Fonts.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "Redesigned/Player/Player.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Pages.h"
#import "Shared/ArtistBlock/ArtistBlock.h"
#import "Shared/Gestures/Gestures.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsMeanings/Meanings.h"
#import "Shared/Player/PlayerSettings.h"
#import "Shared/Sing/Sing.h"
#import "Native/Appearance/Appearance.h"
#import "Native/Navbar/Navbar.h"
#import "Native/NowPlayingBar/NowPlayingBar.h"
#import "Native/Player/NowPlaying.h"
#import "Shared/LiveActivity/LiveActivity.h"
#import "Shared/Lossless/SGLossless.h"
#import "Redesigned/Lyrics/LyricsText.h"
#import "Redesigned/Lyrics/LyricsLook.h"
#import "Redesigned/Lyrics/LyricsTools.h"
#import "Redesigned/Navbar/Navbar.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Redesigned/Kit/SGRAccent.h"

NSString *SGRedesignedUIInfoText(void) {
    return SGL(@"settings.redesign.info", @"The newest version of Vitrine, leaning toward Apple Music's style. It is not compatible with the legacy look's settings.\n\nThe legacy look gives you more freedom, yet still looks like Spotify.");
}

// Below iOS 26 the redesign also needs SGKeyRedesignUntested (Core/SGUIMode.h): whoever calls this has
// shown the warning. Turning it off takes that back, so turning it on again warns again.
void SGSetRedesignedUI(BOOL on) {
    SGSetEnabled(SGKeyRedesign, on);
    SGSetEnabled(SGKeyRedesignUntested, on && !SGRedesignAvailable());
}

NSString *SGRedesignUntestedWarning(void) {
    return [NSString stringWithFormat:SGL(@"settings.redesign.untested.alert.message", @"The redesign is built on iOS 26's Liquid Glass. iOS %@ draws a blur in its place, and nobody has tested the redesign there: pages can be laid out wrongly, and Spotify can freeze as it starts. If Spotify does not start with it, the next launch goes back to Legacy."),
            UIDevice.currentDevice.systemVersion];
}

// The whole look changes hands at launch, so the switch asks for the restart straight away rather than
// leaving Spotify half in the old look.
static void offerRestart(BOOL on) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.redesign.restart.alert.title", @"Restart Spotify")
        message:on ? SGL(@"settings.redesign.restart_on.alert.message", @"The redesign takes over when Spotify starts again. Spotify closes now; open it again to see it.") : SGL(@"settings.redesign.restart_off.alert.message", @"Spotify's own look comes back when Spotify starts again. Spotify closes now; open it again to see it.")
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.later", @"Later") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.redesign.action.restart_now", @"Restart now") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { SGRestartSpotify(); }]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

// Below iOS 26 the switch stores the warning's key, not the look's: it is on only once the warning has
// been accepted, which restarts Spotify at once, so the switch never reads on for a look that is not coming.
static SGModRow *untestedRow(void) {
    SGModRow *row = SGOptionRow(SGL(@"settings.redesign.title", @"Redesigned UI"), [NSString stringWithFormat:SGL(@"settings.redesign.untested.subtitle", @"Untested on iOS %@"), UIDevice.currentDevice.systemVersion], SGKeyRedesignUntested);
    row.glows = YES;
    row.info = SGRedesignedUIInfo;
    row.changed = ^(BOOL on) {
        if (!on) {
            SGSetRedesignedUI(NO);
            offerRestart(NO);
            return;
        }
        SGSetEnabled(SGKeyRedesignUntested, NO);   // the page reloads to off; the warning's button turns it on
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.redesign.confirm.alert.title", @"Turn on the redesign?")
            message:[SGRedesignUntestedWarning() stringByAppendingString:SGL(@"settings.redesign.confirm_restart.alert.message", @"\n\nSpotify restarts to turn it on.")]
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.redesign.action.turn_on_and_restart", @"Turn On and Restart") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            SGSetRedesignedUI(YES);
            SGRestartSpotify();
        }]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    };
    return SGWithTile(row, @"sparkles", UIColor.systemIndigoColor);
}

SGModRow *SGRedesignedUIRow(void) {
    if (!SGRedesignAvailable()) return untestedRow();
    SGModRow *redesign = SGOptionRow(SGL(@"settings.redesign.title", @"Redesigned UI"), nil, SGKeyRedesign);
    redesign.glows = YES;
    redesign.info = SGRedesignedUIInfo;
    redesign.changed = ^(BOOL on) {
        SGSetRedesignedUI(on);
        offerRestart(on);
    };
    return SGWithTile(redesign, @"sparkles", UIColor.systemIndigoColor);
}

// The stored look's own rows, then the font and the app icon, which work under either look on any iOS.
// Redesigned UI itself leads Mod Settings' main page.
UIViewController *SGAppearancePage(void) {
    NSMutableArray<SGModRow *> *everywhere = [NSMutableArray arrayWithArray:SGAppFontRows()];
    SGModRow *icon = SGAppIconRow();
    if (icon) [everywhere addObject:icon];
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.appearance.title", @"Appearance") intro:SGRestartNote sections:@[
        SGSection(nil, SGRedesignedUIStored() ? SGRAppearanceRows() : SGNativeAppearanceRows()),
        SGSection(nil, everywhere),
    ] footer:nil];
}

UIViewController *SGNavbarPage(void) {
    return SGRedesignedUIStored() ? SGRNavbarSettingsPage() : SGNavbarSettingsPage();
}

// One shelf for Vitrine's local and open libraries. AutoEq fetches its public index when Headphones opens,
// and a font still comes from Files. Nothing here depends on a private account or paid catalog.
UIViewController *SGWorkshopPage(void) {
    NSMutableArray<SGModSection *> *sections = [NSMutableArray array];
    if (SGRedesignedUIStored()) {
        [sections addObject:SGSection(SGL(@"settings.workshop.look.header", @"Look"), @[
            SGWithTile(SGPageRow(SGL(@"settings.workshop.visualizers.title", @"Visualizers"), ^UIViewController *{ return SGRVisualiserSettingsPage(); }),
                       @"waveform.path", UIColor.systemPurpleColor),
            SGWithTile(SGPageRow(SGL(@"settings.workshop.lyrics_looks.title", @"Lyrics looks"), ^UIViewController *{ return SGLyricsSettingsPage(); }),
                       @"textformat.size", UIColor.systemOrangeColor),
        ])];
    }

    [sections addObject:SGSection(SGL(@"settings.workshop.sound.header", @"Sound"), @[
        SGWithTile(SGPageRow(SGL(@"settings.workshop.audio_presets.title", @"Audio presets"), ^UIViewController *{ return SGDSPPresetsPage(); }),
                   @"slider.vertical.3", UIColor.systemRedColor),
        SGWithTile(SGPageRow(SGL(@"settings.workshop.headphones.title", @"Headphones"), ^UIViewController *{ return SGDSPHeadphonesPage(); }),
                   @"headphones", UIColor.systemBlueColor),
    ])];

    NSMutableArray<SGModRow *> *fonts = [NSMutableArray array];
    for (SGModRow *row in SGAppFontRows()) [fonts addObject:SGWithTile(row, @"textformat.alt", UIColor.systemIndigoColor)];
    [fonts addObject:SGWithTile(SGPageRow(SGL(@"settings.workshop.free_fonts.title", @"Free fonts"), ^UIViewController *{ return SGFontLibraryPage(); }),
                                @"arrow.down.circle", UIColor.systemTealColor)];
    if (fonts.count) [sections addObject:SGSection(SGL(@"settings.workshop.type.header", @"Type"), fonts)];

    NSString *intro = SGRedesignedUIStored()
        ? SGL(@"settings.workshop.intro.redesigned.v2", @"Built-in and open libraries Vitrine can use without an account. Headphone corrections come from AutoEq, free fonts from Google Fonts. Presets can be shared as files.")
        : SGL(@"settings.workshop.intro.native.v2", @"Built-in and open libraries Vitrine can use without an account. Visualizers and lyrics looks appear here when Redesigned UI is selected. Headphone corrections come from AutoEq, free fonts from Google Fonts. Presets can be shared as files.");
    SGModPage *page = [[SGModPage alloc] initWithTitle:SGL(@"settings.workshop.title", @"Workshop") intro:intro sections:sections footer:nil];
    page.tiles = YES;
    return page;
}

// Pronunciation, romanized lines, translation, word sweeping and line meanings exist only in the redesign's lyrics view.
static UIViewController *lyricsPage(void) {
    BOOL redesigned = SGRedesignedUIStored();
    NSMutableArray<SGModRow *> *more = [NSMutableArray arrayWithObject:SGLockScreenLyricsRow()];
    if (!redesigned) [more insertObject:SGGlassLyricsRow() atIndex:0];
    SGModRow *sing = SGPageRow(SGL(@"settings.lyrics.sing.title", @"Karaoke"), ^UIViewController *{ return SGSingSettingsPage(); });
    sing.value = ^NSString *{ return SGSingSummary(); };
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObjects:SGSection(nil, @[SGWithTile(sing, @"music.mic", UIColor.systemRedColor)]),
                                                SGLyricsSourcesSection(redesigned), nil];
    SGModSection *timing = SGNotedSection(SGL(@"settings.lyrics.timing.header", @"Timing"), @[SGLyricsDelayRow()],
        redesigned ? SGL(@"settings.lyrics.timing.footer.redesigned", @"Every line shows this much later than the song, for Bluetooth headphones that play a little behind the lyrics. "
                         @"Sync in the lyrics' corner menu adds an offset for one song, and one for the headphones it plays through. Applies at once.")
                   : SGL(@"settings.lyrics.timing.footer", @"Every line shows this much later than the song, for Bluetooth headphones that play a little behind the lyrics. Applies at once."));
    if (redesigned) {
        [sections addObjectsFromArray:@[
            SGSection(SGL(@"settings.lyrics.display.header", @"Display"), @[SGRLyricsTextSizesRow(), SGLyricsWordTimingRow(), SGLyricsRomanisedRow(),
                SGLyricsJapaneseReadingRow(), SGLyricsFuriganaRow(), SGRLyricsKeepAwakeRow(),
                SGOptionRow(SGL(@"settings.lyrics.break_labels.title", @"Name the breaks"), SGL(@"settings.lyrics.break_labels.subtitle", @"Intro, Interlude or Outro beside the dots"), SGRKeyLyricsBreakLabels),
                SGSimplifyTitlesRow(),
                SGSwitchRow(SGL(@"settings.lyrics.hide_controls.title", @"Hide the controls"), SGL(@"settings.lyrics.hide_controls.subtitle", @"A few seconds after the last touch, the lyrics take the whole player"), SGRKeyLyricsAutoHide),
                SGSwitchRow(SGL(@"settings.lyrics.landscape.title", @"Landscape lyrics"), SGL(@"settings.lyrics.landscape.subtitle", @"Turn the phone with the lyrics open"), SGRKeyLyricsLandscape)]),
            timing,
            SGSection(SGL(@"settings.lyrics.translation.header", @"Translation"), @[SGLyricsTranslationLanguageRow(), SGTranslateEverySongRow(), SGLyricsLanguageRulesRow(), SGTranslateTitlesRow(), SGGeminiKeyRow(),
                SGClaudeKeyRow(), SGDeepLKeyRow(), SGOpenAIPresetRow(), SGOpenAIKeyRow(), SGBingTranslateRow(), SGGoogleTranslateRow(), SGSavedTranslationsRow()]),
            SGNotedSection(SGL(@"settings.lyrics.ai.header", @"AI"), @[SGLyricsPronunciationNotationRow(), SGLyricsCulturalNotesRow()],
                SGL(@"settings.lyrics.ai.footer", @"Write Pronunciation and Explain References in the lyrics' menu use Gemini, Claude or your AI service, on your own key. What they write is kept for the song.")),
            SGSection(nil, @[SGLyricsMeaningsRow()]),
        ]];
    } else {
        [sections addObject:timing];
    }
    [sections addObject:SGSection(nil, more)];
    // The redesign's page leads with its lyrics playing in the look the page sets, and that look's presets.
    if (redesigned) return SGRLyricsSettingsPage(SGL(@"settings.lyrics.title", @"Lyrics"), SGL(@"settings.lyrics.intro", @"The look applies at once. The settings below apply after you restart Spotify."), sections);
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.lyrics.title", @"Lyrics") intro:SGRestartNote sections:sections footer:nil];
}

// Lyrics has its own row on Mod Settings' main page, beside Sing.
UIViewController *SGLyricsSettingsPage(void) {
    return lyricsPage();
}

UIViewController *SGPlayerSettingsPage(void) {
    SGModRow *blocked = SGPageRow(SGL(@"settings.player.blocked_artists.title", @"Blocked artists"), ^UIViewController *{ return SGArtistBlockSettingsPage(); });
    blocked.value = ^NSString *{
        return SGFlag(SGKeyArtistBlock, NO) ? @(SGBlockedArtists().count).stringValue : SGL(@"common.off", @"Off");
    };
    BOOL native = !SGRedesignedUIStored();

    // AirPods gestures, the lock screen widget and Vibrations have rows of their own on Mod Settings' main page.
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObject:SGSection(nil, @[
        SGWithTile(SGPageRow(SGL(@"settings.player.gestures.title", @"Gestures"), ^UIViewController *{ return SGGesturesSettingsPage(); }), @"hand.tap", UIColor.systemBlueColor),
        SGWithTile(blocked, @"person.crop.circle.badge.xmark", UIColor.systemRedColor),
    ])];
    if (native) {
        [sections addObject:SGSection(nil, @[
            SGWithTile(SGPageRow(SGL(@"settings.player.now_playing_bar.title", @"Now playing bar"), ^UIViewController *{ return SGNowPlayingBarSettingsPage(); }), @"rectangle.bottomthird.inset.filled", UIColor.systemPinkColor),
            SGWithTile(SGPageRow(SGL(@"settings.player.queue_devices.title", @"Queue & devices"), ^UIViewController *{ return SGQueueSettingsPage(); }), @"text.line.first.and.arrowtriangle.forward", UIColor.systemIndigoColor),
        ])];
        [sections addObjectsFromArray:SGNativePlayerScreenSections()];
    }
    // Switch to video is the same chip of Spotify's player under either look.
    [sections addObject:SGSection(native ? nil : SGL(@"settings.player.hide.header", @"Hide on the player"), @[
        SGHideRow(SGL(@"settings.player.hide_video_switch.title", @"Switch to video"), SGL(@"settings.player.hide_video_switch.subtitle", @"The chip over the title of a song with a music video"), SGKeyHideVideoSwitch),
    ])];

    [sections addObject:SGNotedSection(SGL(@"settings.lossless.header", @"Lossless"), @[
        SGOptionRow(SGL(@"settings.lossless.files.title", @"Lossless files"), SGL(@"settings.lossless.files.subtitle", @"Your own FLACs in place of Spotify's stream"), SGKeyLossless),
    ], SGL(@"settings.lossless.footer", @"Put FLAC or ALAC files in Files › Spotify › Lossless. A file plays when its title and length match the song "
       @"and its sound matches what Spotify plays, from about 4 s after the song starts or you seek. Spotify still "
       @"streams its own copy, at its lowest quality while the next song has a file. Karaoke and speeds other than "
       @"1x keep Spotify's sound. Applies after you restart Spotify."))];

    // The redesign's page leads with a card of its player and the background's control, the background's
    // rows and the Mini player section under it.
    if (!native) return SGRPlayerSettingsPage(sections);
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.player.title", @"Player") intro:SGRestartNote sections:sections footer:nil];
}
