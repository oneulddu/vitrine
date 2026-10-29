// Real provider jobs, parser, memo and saved store; only keys/HTTP are fixtures.
static void gapReplies(SGLyricsAI service, NSArray<NSString *> *replies) {
    if (service == SGLyricsAIGemini) geminiTitleReplies = [replies mutableCopy];
    else {
        aiReplies = [NSMutableArray array];
        for (NSString *reply in replies)
            [aiReplies addObject:service == SGLyricsAIClaude ? claudeReply(reply) : chatReply(reply)];
    }
}
static NSString *gapPrompt(SGLyricsAI service) {
    NSURLRequest *request = service == SGLyricsAIGemini ? lastGeminiRequest : lastAIRequest;
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:nil];
    return service == SGLyricsAIGemini ? body[@"contents"][0][@"parts"][0][@"text"]
        : body[@"messages"][service == SGLyricsAIClaude ? 0 : 1][@"content"];
}
static void checkAIGaps(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id savedBase = [defaults objectForKey:SGKeyLyricsOpenAIBaseURL];
    id savedOrder = [defaults objectForKey:SGRKeyLyricsAutoTranslationOrder];
    NSString *savedLanguage = testLanguage;
    BOOL savedAuto = autoRetryEnabled;
    NSSet *savedKeys = testKeys;
    NSMutableDictionary *savedCredentials = openAIKeys;
    testKeys = [NSSet setWithArray:@[@"Vitrine.OpenAI", @"Vitrine.Claude", @"Vitrine.Gemini"]];
    openAIKeys = [@{@"api.openai.com": [@"offline-gap-fixture" dataUsingEncoding:NSUTF8StringEncoding]} mutableCopy];
    [defaults setObject:@"https://api.openai.com/v1" forKey:SGKeyLyricsOpenAIBaseURL];
    testLanguage = @"ko"; autoRetryEnabled = YES;
    CHECK([NSURLProtocol registerClass:SGGeminiTitleProtocol.class]);
    for (NSNumber *provider in @[@(SGLyricsAIOpenAI), @(SGLyricsAIClaude), @(SGLyricsAIGemini)]) {
        SGLyricsAI service = provider.integerValue;
        for (NSNumber *mode in @[@(SGLyricsReplyIndexed), @(SGLyricsReplyJSON), @(SGLyricsReplyProse)]) {
            SGLyricsReplyFormat format = mode.integerValue;
            BOOL indexed = format == SGLyricsReplyIndexed;
            NSString *track = [NSString stringWithFormat:@"gap-%@-%@", provider, mode];
            NSArray *source = @[@"Work comes first", @"You know I am honest", @"Not today"];
            NSArray *expected = @[@"일이 먼저야", @"내가 솔직한 거 알잖아", @"오늘은 안 돼"];
            NSString *partial = indexed ? @"L0001\t일이 먼저야\r\nL0002\t \r\nL0003\t\r\n" : @"[\"일이 먼저야\",\" \",\"\"]";
            NSString *repair = indexed ? @"L0001\t내가 솔직한 거 알잖아\nL0002\t오늘은 안 돼" : @"[\"내가 솔직한 거 알잖아\",\"오늘은 안 돼\"]";
            gapReplies(service, @[partial, repair]);
            NSString *problem = nil;
            NSArray *answer = askLyrics(service, track, aiLines(source), format, &problem);
            // Screenshot-shaped regression: one translated row, all remaining values blank.
            if (![answer isEqual:expected])
                fprintf(stderr, "AI gap: provider=%ld format=%ld returned incomplete rows; screenshot-shaped blank-value reply\n", (long)service, (long)format);
            CHECK([answer isEqual:expected] && !problem);
            NSString *prompt = gapPrompt(service);
            CHECK(![prompt containsString:@"Work comes first"]);
            CHECK([prompt containsString:@"You know I am honest"] && [prompt containsString:@"Not today"]);
            CHECK([askLyrics(service, track, aiLines(source), format, &problem) isEqual:expected] && !problem);
            CHECK(service == SGLyricsAIGemini ? !geminiTitleReplies.count : !aiReplies.count);

            // A second incomplete answer stops with an explicit error and is never memoized.
            NSString *failedTrack = [track stringByAppendingString:@"-failed"];
            NSString *emptyRepair = indexed ? @"L0001\t\nL0002\t" : @"[\"\",\"\"]";
            gapReplies(service, @[partial, emptyRepair]);
            answer = askLyrics(service, failedTrack, aiLines(source), format, &problem);
            CHECK(([answer isEqual:@[@"일이 먼저야", @"", @""]] && problem.length));
            NSArray<SGKaraokeLine *> *saved = aiLines(source);
            saved[0].translation = answer[0]; saved[0].translationMade = YES;
            SGLyricsSaveTranslation(failedTrack, @"ko", saved);
            NSArray<SGKaraokeLine *> *restored = aiLines(source);
            SGLyricsSyncSavedTranslation(failedTrack, @"ko", restored);
            CHECK([restored[0].translation isEqual:@"일이 먼저야"]);
            CHECK(!restored[1].translationMade && !restored[1].translation && !restored[2].translation);
            gapReplies(service, @[partial, repair]);
            CHECK([askLyrics(service, failedTrack, restored, format, &problem) isEqual:expected] && !problem);
            CHECK(service == SGLyricsAIGemini ? !geminiTitleReplies.count : !aiReplies.count);
            SGLyricsDeleteTranslation(failedTrack, @"ko");
        }
        // Missing IDs are gaps, not renumbered sentence positions. Repeated source text and
        // blank/instrumental rows must not move a translated row onto its neighbor.
        NSArray *source = @[@"Echo", @"", @"♪", @"Echo", @"Last"];
        gapReplies(service, @[@"L0001\t메아리\nL0003\t♪", @"L0001\t메아리\nL0002\t마지막"]);
        NSString *problem = nil;
        NSArray *answer = askLyrics(service, nil, aiLines(source), SGLyricsReplyIndexed, &problem);
        CHECK(([answer isEqual:@[@"메아리", @"", @"♪", @"메아리", @"마지막"]] && !problem));
        CHECK([[gapPrompt(service) componentsSeparatedByString:@"\n\n"].lastObject isEqual:@"L0001\tEcho\nL0002\tLast"]);
        gapReplies(service, @[@"L0001\t첫째", @"L0001\t둘째\nL0002\t셋째"]);
        CHECK(([askLyrics(service, nil, aiLines(@[@"First", @"Second", @"Third"]), SGLyricsReplyIndexed, &problem)
                isEqual:@[@"첫째", @"둘째", @"셋째"]] && !problem));

        // Ambiguous/malformed boundaries fail visibly, never guess row shifts or split meanings.
        for (NSString *bad in @[@"L0000\t첫째\nL0001\t둘째", @"L0002\t첫째\nL0003\t둘째",
                                @"L1: 첫째\nL2: 둘째", @"L0001\t첫째\tL0002\t둘째",
                                @"L0001\t첫째\ncontinued\nL0002\t둘째",
                                @"```text\nL0001\t첫째\nL0002\t둘째\n```"]) {
            gapReplies(service, @[bad]);
            CHECK(!askLyrics(service, nil, aiLines(@[@"First", @"Second"]), SGLyricsReplyIndexed, &problem) && problem.length);
        }
        // JSON fences/CRLF are framing; truncated JSON arrays have no reliable missing-row IDs.
        for (NSNumber *mode in @[@(SGLyricsReplyJSON), @(SGLyricsReplyProse)]) {
            gapReplies(service, @[@"```json\r\n[\"첫째\",\"둘째\"]\r\n```"]);
            CHECK(([askLyrics(service, nil, aiLines(@[@"First", @"Second"]), mode.integerValue, &problem)
                    isEqual:@[@"첫째", @"둘째"]] && !problem));
            gapReplies(service, @[@"[\"첫째\"]"]);
            CHECK(!askLyrics(service, nil, aiLines(@[@"First", @"Second"]), mode.integerValue, &problem) && problem.length);
        }
        SGRAutoTranslator translator = service == SGLyricsAIGemini ? SGRAutoTranslatorGemini
            : service == SGLyricsAIClaude ? SGRAutoTranslatorClaude : SGRAutoTranslatorOpenAI;
        [defaults setObject:@[@(translator)] forKey:SGRKeyLyricsAutoTranslationOrder];
        SGRAutoTranslationSettingsChanged();
        NSString *track = [NSString stringWithFormat:@"gap-automatic-%@", provider];
        NSArray<SGKaraokeLine *> *lines = aiLines(@[@"First", @"Second", @"Third"]);
        gapReplies(service, @[@"L0001\t첫째\nL0002\t\nL0003\t", @"L0001\t둘째\nL0002\t셋째"]);
        NSUInteger revision = SGRAutoTranslationClaim(track, @"ko");
        CHECK(revision);
        __block BOOL finished = NO;
        SGRTranslateLyrics(lines, track, @"ko", revision,
            ^(NSArray *sent, NSString *song, NSString *language, SGRAutoTranslated progress, SGRAutoTranslated done) {
                SGRAutoTranslateInOrder(sent, song, language, revision, ^BOOL { return YES; }, progress, done);
            }, nil, ^(NSArray *answer, NSString *error) {
                CHECK(!error); finished = YES;
            });
        waitFor(^BOOL { return finished; });
        SGRAutoTranslationProgress *status = SGRAutoTranslationProgressFor(track, @"ko");
        CHECK(status.phase == SGRAutoTranslationPhaseComplete && status.completed == 3);
        CHECK([lines[0].translation isEqual:@"첫째"] && [lines[1].translation isEqual:@"둘째"] && [lines[2].translation isEqual:@"셋째"]);
        NSArray<SGKaraokeLine *> *restored = aiLines(@[@"First", @"Second", @"Third"]);
        SGLyricsSyncSavedTranslation(track, @"ko", restored);
        CHECK([restored[2].translation isEqual:@"셋째"] && !SGRTranslationJobRunning(track, @"ko"));
        SGLyricsDeleteTranslation(track, @"ko");
    }
    // Two separately legal replies must not bypass the total 128000-UTF16-unit answer cap.
    NSString *large = [@"x" stringByPaddingToLength:64000 withString:@"x" startingAtIndex:0];
    gapReplies(SGLyricsAIOpenAI, @[[NSString stringWithFormat:@"L0001\t%@\nL0002\t%@\nL0003\t", large, large], @"L0001\t셋째"]);
    NSString *problem = nil;
    NSArray *bounded = askLyrics(SGLyricsAIOpenAI, nil, aiLines(@[@"First", @"Second", @"Third"]), SGLyricsReplyIndexed, &problem);
    CHECK(bounded.count == 3 && [bounded[0] length] == 64000 && [bounded[1] length] == 64000 && ![bounded[2] length] && problem.length);
    // Old files may contain whitespace-only "translations". They remain missing after restore.
    NSURL *legacy = [SGLyricsTestCacheRoot() URLByAppendingPathComponent:@"Translations/legacy-gap.ko.json"];
    NSData *legacyData = [NSJSONSerialization dataWithJSONObject:@{@"First": @"첫째", @"Second": @" \r\n"} options:0 error:nil];
    CHECK([legacyData writeToURL:legacy atomically:YES]);
    NSArray<SGKaraokeLine *> *legacyLines = aiLines(@[@"First", @"Second"]);
    SGLyricsSyncSavedTranslation(@"legacy-gap", @"ko", legacyLines);
    CHECK([legacyLines[0].translation isEqual:@"첫째"] && !legacyLines[1].translation && !legacyLines[1].translationMade);
    legacyLines[1].translation = @" \n"; legacyLines[1].translationMade = YES;
    SGLyricsSaveTranslation(@"legacy-gap", @"ko", legacyLines);
    SGLyricsSyncSavedTranslation(@"legacy-gap", @"ko", legacyLines);
    CHECK(!legacyLines[1].translation && !legacyLines[1].translationMade);
    [NSURLProtocol unregisterClass:SGGeminiTitleProtocol.class];
    if (savedBase) [defaults setObject:savedBase forKey:SGKeyLyricsOpenAIBaseURL];
    else [defaults removeObjectForKey:SGKeyLyricsOpenAIBaseURL];
    testKeys = savedKeys; openAIKeys = savedCredentials;
    if (savedOrder) [defaults setObject:savedOrder forKey:SGRKeyLyricsAutoTranslationOrder];
    else [defaults removeObjectForKey:SGRKeyLyricsAutoTranslationOrder];
    testLanguage = savedLanguage; autoRetryEnabled = savedAuto;
    SGRAutoTranslationSettingsChanged();
    aiReplies = nil; geminiTitleReplies = nil;
    SGLyricsDeleteSavedTranslations();
    CHECK([NSFileManager.defaultManager removeItemAtURL:SGLyricsTestCacheRoot() error:nil]);
    puts("AI gaps: three providers/formats repair blanks once, preserve indices, reject ambiguity, report exhaustion, and never memoize partial results");
}
