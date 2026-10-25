#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "About.h"
#import "App/Onboarding/Onboarding.h"
#import "Shared/AutoMix/AutoMix.h"
#import "Shared/Lossless/LosslessQuality.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"

// Every key of the mod's is under one prefix, so a reset is a sweep of the defaults with the stock
// marker of SGPrefs.h left behind; the hooks read them at launch, so it ends in a restart.
static void resetAll(void) {
    // Spotify's own settings that AutoMix and Lossless changed go back first, while the keys that hold them are there.
    SGAutoMixApply(NO);
    SGLosslessLowerQuality(NO);
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    NSUInteger removed = 0;
    for (NSString *key in [store persistentDomainForName:NSBundle.mainBundle.bundleIdentifier].allKeys) {
        if (![key hasPrefix:@"spotifyglass."]) continue;
        [store removeObjectForKey:key];
        removed++;
    }
    [store setBool:YES forKey:SGKeyStock];
    SGLog(@"reset: removed %lu keys", (unsigned long)removed);
    SGRestartSpotify();
}

static void confirmReset(void) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.mod.reset.alert.title", @"Reset all settings?")
                                                                  message:SGL(@"settings.mod.reset.alert.message", @"Every switch and lyrics source turns off, flag overrides and the tab bar layout are cleared, and Spotify restarts as it came, with the mod doing nothing until asked. Spotify settings changed by AutoMix and Lossless are restored.")
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.mod.reset.action.reset_and_restart", @"Reset and restart") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { resetAll(); }]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

// Reset all leaves the Keychain alone, so a key outlives a reset; this takes every item Vitrine keeps there,
// by each service's own name, and keeps the settings.
static void confirmClearKeychain(void) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.mod.keychain.alert.title", @"Clear Keychain?")
                                                                  message:SGL(@"settings.mod.keychain.alert.message", @"The Gemini, Claude, OpenAI-compatible and DeepL API keys, the Spicy Lyrics key and the Deezer ARL are removed from this iPhone. Settings stay as they are.")
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.mod.keychain.action.clear", @"Clear Keychain") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        SGGeminiForgetKey();
        SGClaudeForgetKey();
        SGOpenAIForgetKeys();
        SGDeepLForgetKey();
        SGSpicyLyricsForgetKey();
        SGDeezerForgetKey();
        // The translators' rows, their pages and the lyrics menu follow this notification, as their own
        // Remove does. The lyrics sources read their key at each ask; their rows and the lyrics view hear
        // the sources' own change, so the track playing is announced reloaded and builds its lines again.
        SGLyricsTranslationServiceSettingsChanged();
        NSString *playing = SGKaraokePlayingTrack();
        if (playing.length) [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsDidReloadNotification object:playing];
        SGLog(@"reset: keychain cleared");
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static SGModRow *withSymbol(SGModRow *row, NSString *symbol) {
    row.symbol = symbol;
    return row;
}

// Which build this is, whether GitHub has a newer release, and where to reach the mod: without these
// rows a build that is already installed has no way of telling its user that anything moved on.
UIViewController *SGAboutPage(void) {
    __block __weak SGModPage *owner = nil;
    SGModRow *reset = withSymbol(SGActionRow(SGL(@"settings.mod.reset.title", @"Reset all settings"), nil, ^{ confirmReset(); }), @"trash");
    reset.color = SGRed();
    // Reset all removes the settings; the keys live in the Keychain, which it leaves alone, so this takes them.
    SGModRow *clearKeys = withSymbol(SGActionRow(SGL(@"settings.mod.keychain.title", @"Clear Keychain"), nil, ^{ confirmClearKeychain(); }), @"key");
    clearKeys.color = SGRed();
    NSString *spotify = SGSpotifyVersion();
    if ([SGSpotifyLikelyWorksVersions containsObject:spotify]) spotify = [spotify stringByAppendingString:SGL(@"settings.mod.spotify_version.likely_works", @", likely works")];
    else if (![SGSpotifySupportedVersions containsObject:spotify]) spotify = [NSString stringWithFormat:SGL(@"settings.mod.spotify_version.made_for", @"%@, made for %@"), spotify, SGSpotifyMadeFor];
    // The row reads out where the build stands and opens the changelog of everything newer than it.
    SGModRow *updates = SGPageRow(SGL(@"settings.mod.updates.title", @"Updates"), ^UIViewController *{ return SGUpdatePage(); });
    updates.value = ^NSString *{ return SGUpdateStatus(); };
    // A release build can opt into betas; a beta build starts opted in. Either way a check follows at
    // once, since the stored list only holds what counted at the last one.
    SGModRow *betas = SGSwitchRow(SGL(@"settings.mod.include_betas.title", @"Include betas"), SGL(@"settings.mod.include_betas.subtitle", @"Offer test builds ahead of each release"), SGKeyUpdateBetas);
    betas.defaultOn = SGBuildIsBeta();
    betas.changed = ^(BOOL on) { SGCheckForUpdate(YES); };
    NSMutableArray<SGModRow *> *links = [NSMutableArray array];
    if (SGRepoURL) [links addObject:withSymbol(SGLinkRow(@"GitHub", nil, SGRepoURL), @"chevron.left.forwardslash.chevron.right")];
    [links addObjectsFromArray:@[
        withSymbol(SGPageRow(SGL(@"settings.mod.licenses.title", @"Licenses"), ^UIViewController *{ return SGLicensesPage(); }), @"doc.text"),
        withSymbol(SGActionRow(SGL(@"settings.mod.tour.title", @"Welcome tour"), nil, ^{ SGShowOnboarding(); }), @"map"),
    ]];
    if (SGWhatsNewChanges().count) [links insertObject:withSymbol(SGActionRow(SGL(@"settings.mod.whats_new.title", @"What's New"), nil, ^{ SGShowWhatsNew(); }), @"sparkles") atIndex:links.count - 1];
    NSMutableArray<SGModRow *> *build = [NSMutableArray arrayWithObjects:updates, betas,
        SGStatRow(SGL(@"settings.mod.version.title", @"Version"), ^NSString *{ return @(SG_VERSION); }),
        SGStatRow(@"Spotify", ^NSString *{ return spotify; }), nil];
    SGModRow *signedUntil = SGSigningExpiryRow();
    if (signedUntil) [build addObject:signedUntil];
    SGModPage *page = [[SGModPage alloc] initWithTitle:SGL(@"settings.mod.title", @"Mod") intro:nil sections:@[
        SGSection(nil, build),
        SGSection(nil, links),
        SGSection(nil, @[
            withSymbol(SGActionRow(SGL(@"settings.mod.export_settings.title", @"Export settings"), nil, ^{ SGExportSettings(); }), @"square.and.arrow.up"),
            withSymbol(SGActionRow(SGL(@"settings.mod.import_settings.title", @"Import settings"), nil, ^{ SGImportSettings(); }), @"square.and.arrow.down"),
            withSymbol(SGActionRow(SGL(@"settings.mod.share_diagnostics.title", @"Share diagnostics"), SGL(@"settings.mod.share_diagnostics.subtitle", @"For a bug report: versions, ad counts, this launch's log and Spotify's config. Song names can show."),
                                   ^{ SGShareDiagnostics(owner); }), @"stethoscope"),
            SGWithNew(withSymbol(SGPageRow(SGL(@"settings.mod.report.title", @"Report a problem"), ^UIViewController *{ return SGReportListPage(); }), @"exclamationmark.bubble"), @"reportProblem"),
        ]),
        SGSection(nil, @[clearKeys, reset]),
    ] footer:nil];
    owner = page;
    return page;
}
