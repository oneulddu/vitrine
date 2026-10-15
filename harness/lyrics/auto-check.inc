// Included by translation-check.m: real view, real automatic scheduler and provider chain, offline services.
extern NSString *SGHarnessPlayingTrack;
extern void (^SGHarnessOpenAI)(NSArray<SGKaraokeLine *> *, SGHarnessDone);
extern void (^SGHarnessBing)(NSArray<SGKaraokeLine *> *, SGHarnessDone);
static SGRKaraokeView *autoPlayer, *autoPage;
static UIView *autoPlayerHost, *autoPageHost;
static NSUInteger googleCalls, bingCalls;
static void autoTick(SGRKaraokeView *view);
static void pump(void) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:0.55];
    while (until.timeIntervalSinceNow > 0) {
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        autoTick(autoPlayer); autoTick(autoPage);
    }
}
static void autoTick(SGRKaraokeView *view) {
    ((void (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"tick"));
    [view layoutSubviews]; // The host normally lays out the initially hidden lyrics before their first display frame.
}
static NSArray<SGKaraokeLine *> *autoSong(NSString *track) {
    SGHarnessPlayingTrack = track;
    SGKaraokeLine *source = sungLine(1000, @"uno dos"); source.translation = @"source";
    NSArray *lines = @[source, sungLine(4000, @"tres cuatro"), sungLine(7000, @"cinco seis")];
    SGKaraokeKeepLines(track, lines);
    autoTick(autoPlayer); autoTick(autoPage);
    return lines;
}
static void autoSetup(BOOL enabled) {
    NSUserDefaults *args = NSUserDefaults.standardUserDefaults;
    [args setBool:enabled forKey:SGRKeyLyricsAutoTranslation];
    [args setBool:YES forKey:SGKeyLyricsGoogleTranslate]; [args setBool:YES forKey:SGKeyLyricsBingTranslate];
    [args setBool:NO forKey:@"gemini"]; [args setBool:NO forKey:@"openai"];
    [args setBool:NO forKey:@"onDevice"]; [args setBool:NO forKey:@"intelligence"];
    [args removeObjectForKey:@"translateTo"];
    SGRAutoTranslationSettingsChanged();
    SGRSetLyricsTextShown(SGRLyricsTextTranslation, YES);
    googleCalls = bingCalls = 0; sg_alert = nil; sg_held = nil;
    SGHarnessGoogle = ^(NSArray *lines, SGHarnessDone done) { googleCalls++; done(nil, @"failed"); done(nil, @"duplicate"); };
    SGHarnessBing = ^(NSArray *lines, SGHarnessDone done) { bingCalls++; done(markAll(lines, @"B: "), nil); };
}
static void autoCheck(UIWindow *window) {
    NSUserDefaults *args = NSUserDefaults.standardUserDefaults;
    UIViewController *root = [UIViewController new]; window.rootViewController = root;
    [window makeKeyAndVisible];
    CGRect bounds = root.view.bounds;
    autoPlayer = [[SGRKaraokeView alloc] initWithFrame:CGRectMake(0, 0, bounds.size.width, bounds.size.height / 2)];
    autoPage = [[SGRKaraokeView alloc] initWithFrame:CGRectMake(0, bounds.size.height / 2, bounds.size.width, bounds.size.height / 2)];
    autoPlayerHost = [[UIView alloc] initWithFrame:root.view.bounds]; autoPageHost = [[UIView alloc] initWithFrame:root.view.bounds];
    [root.view addSubview:autoPlayerHost]; [root.view addSubview:autoPageHost];
    [autoPlayerHost addSubview:autoPlayer]; [autoPageHost addSubview:autoPage];
    autoSetup(NO);
    check(!SGRAutoTranslationEnabled(), @"auto is off by default");
    check([SGRAutoTranslationOrder().firstObject isEqual:@(SGRAutoTranslatorOnDevice)] && SGRAutoTranslationOrder().count == 8, @"default order contains all eight translators, local first");
    SGRSetAutoTranslationOrder((id)@[@3, @3, @99, @"bad", @4]);
    check(SGRAutoTranslationOrder().count == 8 && [SGRAutoTranslationOrder()[0] isEqual:@3] && [SGRAutoTranslationOrder()[1] isEqual:@4], @"invalid and duplicate order entries are repaired");
    autoSong(@"auto-off"); pump();
    check(googleCalls == 0 && bingCalls == 0, @"off sends nothing from either view");
    autoSetup(YES);
    NSArray *lines = autoSong(@"auto-fallback"); pump();

    check(googleCalls == 1 && bingCalls == 1, @"two views share one Google failure then one Bing request");
    check([translations(lines) isEqual:@"source | B: tres cuatro* | B: cinco seis*"], @"fallback fills gaps and preserves source translation");
    check(!spinning(autoPlayer) && !spinning(autoPage) && !sg_alert, @"automatic fallback ends both spinners without alerts");
    // Recreate lines like returning to a song or a provider refining its timing; saved results suffice.
    [autoPlayer setValue:nil forKey:@"lines"]; [autoPage setValue:nil forKey:@"lines"];
    lines = autoSong(@"auto-fallback"); pump();
    check(googleCalls == 1 && bingCalls == 1 && ((SGKaraokeLine *)lines[1]).translation.length, @"saved translation is reused without a new chain");

    autoSetup(YES);
    SGHarnessGoogle = ^(NSArray *sent, SGHarnessDone done) { googleCalls++; done(@[@"", @"first part", @""], @"partial"); };
    lines = autoSong(@"auto-partial"); pump();
    check(googleCalls == 1 && bingCalls == 1 && [translations(lines) isEqual:@"source | first part* | B: cinco seis*"], @"partial success survives the next provider");
    tap(item(autoPlayer, @"Remove Translation")); pump();
    ((void (*)(id, SEL))objc_msgSend)(autoPage, NSSelectorFromString(@"timeLines")); pump();
    check(googleCalls == 1 && bingCalls == 1 && [translations(lines) isEqual:@"source | - | -"], @"removal suppresses regeneration in all views");
    check(tap(item(autoPlayer, @"Translate with Google")), @"manual translation remains available after automatic removal");
    pump(); check(googleCalls == 2 && bingCalls == 1, @"manual partial retry never triggers automatic fallback");

    autoSetup(YES);
    SGHarnessBing = ^(NSArray *sent, SGHarnessDone done) { bingCalls++; done(nil, @"failed"); };
    autoSong(@"auto-all-failed"); pump(); pump();
    ((void (*)(id, SEL))objc_msgSend)(autoPlayer, NSSelectorFromString(@"timeLines")); pump();
    check(googleCalls == 1 && bingCalls == 1 && !sg_alert && !spinning(autoPlayer), @"all-failed chain stops once without alert or retry loop");
    [args setBool:NO forKey:SGKeyLyricsCulturalNotes];
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil]; pump();
    [NSNotificationCenter.defaultCenter postNotificationName:SGTitleTranslationSettingsDidChangeNotification object:nil]; pump();
    check(googleCalls == 1 && bingCalls == 1, @"note/title display notifications never retry a failed automatic chain");

    autoSetup(YES);
    SGHarnessGoogle = ^(NSArray *sent, SGHarnessDone done) { googleCalls++; sg_held = done; };
    lines = autoSong(@"auto-cancel"); pump();
    SGHarnessDone stale = sg_held;
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil]; pump();
    check(googleCalls == 1 && bingCalls == 0 && spinning(autoPlayer), @"generic display refresh keeps an in-flight chain and its token");
    [args setBool:NO forKey:SGRKeyLyricsAutoTranslation]; SGRAutoTranslationSettingsChanged();
    if (stale) stale(nil, @"failed"); pump();
    check(googleCalls == 1 && bingCalls == 0 && [translations(lines) isEqual:@"source | - | -"], @"switching off cancels the pending answer and its fallback");

    autoSetup(YES);
    SGHarnessGoogle = ^(NSArray *sent, SGHarnessDone done) { googleCalls++; sg_held = done; };
    lines = autoSong(@"auto-reorder"); pump(); stale = sg_held;
    SGRSetAutoTranslationOrder(@[@4, @3]); pump();
    if (stale) stale(markAll(lines, @"old: "), nil); pump();
    check(googleCalls == 1 && bingCalls == 1 && [translations(lines) isEqual:@"source | B: tres cuatro* | B: cinco seis*"], @"reorder starts new priority and rejects the old answer");

    SGRSetAutoTranslationOrder(@[@3, @4]); autoSetup(YES);
    SGHarnessGoogle = ^(NSArray *sent, SGHarnessDone done) { googleCalls++; sg_held = done; };
    lines = autoSong(@"auto-hide"); pump();
    tap(item(autoPlayer, @"Hide Translation"));
    if (sg_held) sg_held(@[@"", @"hidden part", @""], @"partial"); pump();
    check(!shown() && bingCalls == 0 && [((SGKaraokeLine *)lines[1]).translation isEqual:@"hidden part"], @"hiding retains an in-flight partial answer but stops further providers");
    lines = autoSong(@"auto-hidden-new"); pump();
    check(googleCalls == 1 && item(autoPlayer, @"Show Translation"), @"hidden new song sends nothing and still offers Show Translation");
    tap(item(autoPlayer, @"Show Translation")); pump();
    check(googleCalls == 2, @"Show Translation resumes automatic requests");
    SGHarnessDeleteAllTranslations(); if (sg_held) sg_held(markAll(lines, @"deleted: "), nil); pump();
    check(bingCalls == 0 && !SGHarnessSavedTranslations[@"auto-hidden-new|en"], @"clear-all prevents a late answer or immediate automatic regeneration");

    autoSetup(YES); [args setBool:NO forKey:SGKeyLyricsGoogleTranslate]; [args setBool:NO forKey:SGKeyLyricsBingTranslate];
    lines = autoSong(@"auto-no-service"); pump();
    check(!googleCalls && !bingCalls, @"unavailable services are skipped without consuming an attempt");
    [args setBool:YES forKey:SGKeyLyricsBingTranslate];
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationServiceSettingsDidChangeNotification object:nil]; pump();
    check(bingCalls == 1 && !googleCalls, @"enabling a service later translates the same song");

    autoSetup(YES);
    SGHarnessGoogle = ^(NSArray *sent, SGHarnessDone done) { googleCalls++; sg_held = done; };
    lines = autoSong(@"auto-target"); pump(); stale = sg_held;
    [args setObject:@"ko" forKey:@"translateTo"];
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil]; pump();
    if (stale) stale(markAll(lines, @"old language: "), nil);
    if (sg_held) sg_held(markAll(lines, @"new language: "), nil); pump();
    check(googleCalls == 2 && bingCalls == 0 && [((SGKaraokeLine *)lines[1]).translation hasPrefix:@"new language:"], @"target change rejects the old reply and starts only the new target");

    autoSetup(YES);
    SGHarnessGoogle = ^(NSArray *sent, SGHarnessDone done) { googleCalls++; sg_held = done; };
    autoSong(@"auto-old-song"); pump(); stale = sg_held;
    SGHarnessGoogle = ^(NSArray *sent, SGHarnessDone done) { googleCalls++; done(markAll(sent, @"new song: "), nil); };
    lines = autoSong(@"auto-new-song"); pump();
    if (stale) stale(nil, @"failed late"); pump();
    check(googleCalls == 2 && bingCalls == 0 && [((SGKaraokeLine *)lines[1]).translation hasPrefix:@"new song:"], @"track switch prevents the previous song's fallback from starting");

    autoSetup(YES);
    SGLyricsSetTrackLanguage(@"auto-rule-off", @"es");
    SGLyricsSetLanguageRule(@"es", NO, NO);
    autoSong(@"auto-rule-off"); pump();
    check(googleCalls == 0 && bingCalls == 0, @"language rule off prevents automatic requests");
    [args removeObjectForKey:SGKeyLyricsLanguageRules];
    SGLyricsSetTrackLanguage(@"auto-rule-off", nil);
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsLanguageDidChangeNotification object:nil];

    autoSetup(YES); [args setBool:YES forKey:@"openai"];
    SGHarnessBing = ^(NSArray *sent, SGHarnessDone done) { bingCalls++; done(nil, @"failed"); };
    __block NSUInteger openAICalls = 0;
    SGHarnessOpenAI = ^(NSArray *sent, SGHarnessDone done) { openAICalls++; done(markAll(sent, @"AI: "), nil); };
    lines = autoSong(@"auto-custom-ai"); pump();
    check(googleCalls == 1 && bingCalls == 1 && openAICalls == 1 && [((SGKaraokeLine *)lines[1]).translation hasPrefix:@"AI:"], @"configured AI service follows failed translators; missing-key services are skipped");
    SGHarnessOpenAI = nil;

    autoSetup(YES);
    [autoPlayer removeFromSuperview]; [autoPage removeFromSuperview];
    autoSong(@"auto-not-visible"); pump();
    check(!googleCalls && !bingCalls, @"detached lyrics views send nothing");
    [autoPlayerHost addSubview:autoPlayer]; [autoPageHost addSubview:autoPage]; pump();
    check(googleCalls == 1 && bingCalls == 1, @"attaching lyrics starts one shared chain");
    [args setBool:NO forKey:SGRKeyLyricsAutoTranslation]; SGRAutoTranslationSettingsChanged();
    [autoPlayer removeFromSuperview]; [autoPage removeFromSuperview]; autoPlayer = autoPage = nil;
    SGHarnessPlayingTrack = nil;
}
