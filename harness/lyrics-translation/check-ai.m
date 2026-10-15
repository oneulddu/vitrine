// Included by check.m so the scripted transport and row stand-ins are shared with the earlier checks.
static NSArray *aiLines(NSArray *texts) {
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *text in texts) {
        SGKaraokeWord *word = [SGKaraokeWord new]; word.text = text;
        SGKaraokeLine *line = [SGKaraokeLine new]; line.words = @[word];
        [lines addObject:line];
    }
    return lines;
}
static id claudeReply(NSString *text) { return @{@"content": @[@{@"type": @"text", @"text": text}], @"stop_reason": @"end_turn"}; }
static void waitFor(BOOL (^ready)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!ready() && deadline.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    CHECK(ready());
}
static NSArray *askAI(SGLyricsAI service, NSString *track, NSArray *texts, BOOL notes, NSString **problem) {
    __block NSUInteger calls = 0;
    __block NSArray *out;
    __block NSString *failure;
    void (^done)(NSArray *, NSString *) = ^(NSArray *answer, NSString *error) {
        CHECK(NSThread.isMainThread && ++calls == 1);
        out = answer; failure = error;
    };
    if (notes) SGLyricsAINotes(service, track, aiLines(texts), @"ko", done);
    else SGLyricsAIPronounce(service, track, aiLines(texts), done);
    waitFor(^BOOL { return calls > 0; });
    if (problem) *problem = failure;
    return out;
}
static void checkOpenAIHostKeys(void) {
    CHECK([SGOpenAIKeyHost(nil) isEqual:@"api.openai.com"]);
    CHECK([SGOpenAIKeyHost(@"https://OpenRouter.AI:443/api/v1/") isEqual:@"openrouter.ai"]);
    CHECK([SGOpenAIKeyHost(@"https://api.openai.com/other-path") isEqual:@"api.openai.com"]);
    CHECK([SGOpenAIKeyHost(@"http://LOCALHOST:8080/v1") isEqual:@"localhost"]);
    CHECK([SGOpenAIKeyHost(@"http://127.0.0.1:8080") isEqual:@"127.0.0.1"]);
    CHECK([SGOpenAIKeyHost(@"http://Server.LOCAL/v1") isEqual:@"server.local"]);
    CHECK([SGOpenAIKeyHost(@"http://100.97.8.81:10100/v1") isEqual:@"100.97.8.81"]);
    for (id bad in @[@"", @"/v1", @"https://user:pass@openrouter.ai/v1", @"https://api.openai.com/v1?x=1", @"https://api.openai.com/#x", @"http://openrouter.ai", @42]) CHECK(!SGOpenAIKeyHost(bad));
    CHECK(SGOpenAIKeyMigrationDecision(nil, NO, NO) == SGOpenAIKeyMigrationNone);
    CHECK(SGOpenAIKeyMigrationDecision(nil, YES, NO) == SGOpenAIKeyMigrationCopy);
    CHECK(SGOpenAIKeyMigrationDecision(@"invalid", YES, NO) == SGOpenAIKeyMigrationDeferred);
    CHECK(SGOpenAIKeyMigrationDecision(@"invalid", YES, YES) == SGOpenAIKeyMigrationDeferred);
    CHECK(SGOpenAIKeyMigrationDecision(@"https://openrouter.ai/api/v1", YES, YES) == SGOpenAIKeyMigrationDeleteLegacy);

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSData *legacy = [@"router-key" dataUsingEncoding:NSUTF8StringEncoding];
    testKeys = [NSSet setWithObject:@"Vitrine.OpenAI"];
    openAIKeys = [@{@"api-key": legacy} mutableCopy];
    [defaults removeObjectForKey:SGKeyLyricsOpenAIBaseURL];
    CHECK(SGOpenAIKeySet() && [openAIKeys[@"api.openai.com"] isEqual:legacy] && !openAIKeys[@"api-key"]);
    [defaults setObject:@"https://OpenRouter.AI/api/v1" forKey:SGKeyLyricsOpenAIBaseURL];
    openAIKeys = [@{@"api-key": legacy} mutableCopy];
    SGModRow *row = SGOpenAIPresetRow();
    row.chosen(2); // Migration must use the old URL even without a prior key lookup.
    CHECK([openAIKeys[@"openrouter.ai"] isEqual:legacy] && !openAIKeys[@"api-key"] && !openAIKeys[@"api.groq.com"]);
    CHECK(!SGOpenAIKeySet() && SGLyricsAIAvailable().count == 0 && [row.value() isEqual:@"Groq · no key"]);
    NSString *problem = nil;
    CHECK(!SGOpenAIRequest(@"system", @"prompt", &problem) && problem.length);
    NSUInteger before = aiRequests;
    CHECK(!askAI(SGLyricsAIOpenAI, @"host-missing-job", @[@"Blue robot"], YES, &problem) && problem.length && aiRequests == before);
    __block BOOL finished = NO;
    SGLyricsTranslateWithOpenAI(@"host-missing-lyrics", aiLines(@[@"Blue robot"]), @"ko", ^(NSArray *answer, NSString *error) {
        CHECK(!answer && error.length); finished = YES;
    });
    waitFor(^BOOL { return finished; });
    titlesEnabled = YES; deviceAvailable = NO; testLanguage = @"ko";
    SGLyricsTranslatedTitle(@"host-missing-title", @"Blue robot", @"Artist", NULL);
    dispatch_async(dispatch_get_main_queue(), ^{ finished = NO; });
    waitFor(^BOOL { return !finished; });
    CHECK(aiRequests == before);

    row.chosen(1);
    CHECK(SGOpenAIKeySet() && [row.value() isEqual:@"OpenRouter"]);
    NSURLRequest *request = SGOpenAIRequest(@"system", @"prompt", &problem);
    CHECK([request.URL.host isEqual:@"openrouter.ai"] && [[request valueForHTTPHeaderField:@"Authorization"] isEqual:@"Bearer router-key"]);
    aiReplies = [NSMutableArray arrayWithObject:chatReply(@"[\"로봇\",\"가수\"]")];
    SGLyricsTranslatedTitle(@"host-key-title", @"Blue robot", @"Artist", NULL);
    waitFor(^BOOL { return SGLyricsTranslatedTitle(@"host-key-title", @"Blue robot", @"Artist", NULL) != nil; });
    CHECK([lastAIRequest.URL.host isEqual:@"openrouter.ai"] && [[lastAIRequest valueForHTTPHeaderField:@"Authorization"] isEqual:@"Bearer router-key"]);
    CHECK(aiRequests == before + 1);
    titlesEnabled = NO; testLanguage = nil;

    openAIKeys[@"api.groq.com"] = [@"groq-key" dataUsingEncoding:NSUTF8StringEncoding];
    row.chosen(2);
    request = SGOpenAIRequest(@"system", @"prompt", &problem);
    CHECK([request.URL.host isEqual:@"api.groq.com"] && [[request valueForHTTPHeaderField:@"Authorization"] isEqual:@"Bearer groq-key"]);
    openAIKeys[@"api-key"] = legacy;
    CHECK(SGOpenAIKeySet() && !openAIKeys[@"api-key"] && [[SGOpenAIRequest(@"system", @"prompt", &problem) valueForHTTPHeaderField:@"Authorization"] isEqual:@"Bearer groq-key"]);

    [defaults setObject:@"https://openrouter.ai/api/v1" forKey:SGKeyLyricsOpenAIBaseURL];
    openAIKeys = [@{@"api-key": legacy} mutableCopy];
    keyWriteFailure = errSecInteractionNotAllowed;
    row.chosen(2);
    CHECK([SGOpenAIPresetName() isEqual:@"OpenRouter"] && openAIKeys[@"api-key"] && !openAIKeys[@"api.groq.com"] && !SGOpenAIKeySet());
    keyWriteFailure = 0;
    keyDeleteFailure = errSecInteractionNotAllowed;
    row.chosen(2);
    CHECK([SGOpenAIPresetName() isEqual:@"OpenRouter"] && openAIKeys[@"api-key"] && openAIKeys[@"openrouter.ai"] && !SGOpenAIKeySet());
    keyDeleteFailure = 0;
    row.chosen(2);
    CHECK(!openAIKeys[@"api-key"] && !SGOpenAIKeySet());
    keyReadFailure = errSecInteractionNotAllowed;
    row.chosen(1);
    CHECK([SGOpenAIPresetName() isEqual:@"Groq"]);
    keyReadFailure = 0;
    [defaults setObject:@"invalid" forKey:SGKeyLyricsOpenAIBaseURL];
    openAIKeys = [@{@"api-key": legacy} mutableCopy];
    CHECK(!SGOpenAIKeySet() && openAIKeys[@"api-key"] && openAIKeys.count == 1);
    [defaults setObject:@"http://100.97.8.81:10100/v1" forKey:SGKeyLyricsOpenAIBaseURL];
    openAIKeys = [@{@"100.97.8.81": [@"tailnet-test-key" dataUsingEncoding:NSUTF8StringEncoding]} mutableCopy];
    NSURLRequest *tailnet = SGOpenAIRequest(@"system", @"prompt", &problem);
    CHECK([tailnet.URL.absoluteString isEqual:@"http://100.97.8.81:10100/v1/chat/completions"]);
    CHECK([[tailnet valueForHTTPHeaderField:@"Authorization"] isEqual:@"Bearer tailnet-test-key"]);
    [defaults setObject:@"http://100.97.8.82:10100/v1" forKey:SGKeyLyricsOpenAIBaseURL];
    CHECK(!SGOpenAIKeySet());
    testKeys = [NSSet set]; openAIKeys = nil;
    puts("OpenAI keys: host derivation, migration decisions, failure retry, preset isolation and lyrics/AI/title request guards passed");
}
static void checkClaudeAndPresets(void) {
    NSString *problem = @"old";
    CHECK(([SGClaudeTranslationsIn(@{@"content": @[@{@"type": @"thinking", @"thinking": @"ignore"}, @{@"type": @"text", @"text": @"[\"A\","}, @{@"type": @"text", @"text": @"\"B\"]"}]}, 200, nil, 2, &problem) isEqual:@[@"A", @"B"]] && !problem));
    CHECK(([SGClaudeTranslationsIn(claudeReply(@"```json\n[\"A\",\"\"]\n```"), 200, nil, 2, &problem) isEqual:@[@"A", @""]]));
    CHECK(!SGClaudeTranslationsIn(claudeReply(@"[\"A\"]"), 200, nil, 2, &problem) && problem.length);
    for (id bad in @[NSNull.null, @{}, @{@"content": @[@42]}, @{@"content": @[@{@"type": @"text", @"text": @42}]}, claudeReply(@"[1]"), claudeReply(@"```xml\n[\"A\"]\n```")]) {
        CHECK(!SGClaudeTranslationsIn(bad, 200, nil, 1, &problem) && problem.length);
    }
    CHECK(!SGClaudeTranslationsIn(@{@"content": @[@{@"type": @"text", @"text": @"[\"A\"]"}], @"stop_reason": @"max_tokens"}, 200, nil, 1, &problem));
    CHECK(!SGClaudeTranslationsIn(@{@"error": @{@"message": @"Unknown model test-model"}}, 400, nil, 1, &problem) && [problem containsString:@"Unknown model test-model"]);
    for (NSNumber *status in @[@401, @403]) CHECK(!SGClaudeTranslationsIn(claudeReply(@"[\"A\"]"), status.integerValue, nil, 1, &problem) && [problem containsString:@"key"]);
    for (NSNumber *status in @[@429, @500, @529, @599]) CHECK(!SGClaudeTranslationsIn(@{}, status.integerValue, nil, 1, &problem) && [problem containsString:@"busy"]);
    CHECK(!SGClaudeTranslationsIn(@{}, 400, nil, 1, &problem) && [problem containsString:@"400"]);
    CHECK(!SGClaudeTranslationsIn(@{}, 200, [NSError errorWithDomain:NSURLErrorDomain code:-1 userInfo:nil], 1, &problem) && [problem containsString:@"reached"]);
    CHECK(!SGClaudeTranslationsIn(claudeReply([@"A" stringByPaddingToLength:256001 withString:@"A" startingAtIndex:0]), 200, nil, 1, &problem));
    CHECK(!SGClaudeTranslationsIn(@{}, 200, nil, 1, NULL));

    NSArray *expected = @[@[@"OpenAI", @"https://api.openai.com/v1/chat/completions", @"gpt-4o-mini"],
        @[@"OpenRouter", @"https://openrouter.ai/api/v1/chat/completions", @"openai/gpt-4o-mini"],
        @[@"Groq", @"https://api.groq.com/openai/v1/chat/completions", @"llama-3.3-70b-versatile"],
        @[@"Perplexity", @"https://api.perplexity.ai/chat/completions", @"sonar"],
        @[@"Pollinations", @"https://gen.pollinations.ai/chat/completions", @"openai"]];
    NSArray *presets = SGOpenAIPresets();
    CHECK(presets.count == expected.count);
    SGModRow *row = SGOpenAIPresetRow();
    CHECK(row.menu.count == 6);
    for (NSUInteger i = 0; i < presets.count; i++) {
        CHECK([presets[i][@"name"] isEqual:expected[i][0]]);
        CHECK([SGOpenAICompletionURL(presets[i][@"base"]).absoluteString isEqual:expected[i][1]]);
        CHECK([presets[i][@"model"] isEqual:expected[i][2]]);
        row.chosen(i);
        CHECK([NSUserDefaults.standardUserDefaults stringForKey:SGKeyLyricsOpenAIBaseURL] && [row.value() isEqual:[expected[i][0] stringByAppendingString:@" · no key"]]);
        CHECK([[NSUserDefaults.standardUserDefaults stringForKey:SGKeyLyricsOpenAIModel] isEqual:expected[i][2]]);
        CHECK([SGLyricsAIName(SGLyricsAIOpenAI) isEqual:expected[i][0]]);
    }
    row.chosen(5);
    CHECK([row.value() isEqual:@"Pollinations · no key"]);
    [NSUserDefaults.standardUserDefaults setObject:@"https://custom.example/v1" forKey:SGKeyLyricsOpenAIBaseURL];
    CHECK([row.value() isEqual:@"Custom · no key"] && [SGLyricsAIName(SGLyricsAIOpenAI) isEqual:@"your AI service"]);
    [NSUserDefaults.standardUserDefaults setObject:@"https://openrouter.ai/api/v1/" forKey:SGKeyLyricsOpenAIBaseURL];
    CHECK([SGOpenAIPresetName() isEqual:@"OpenRouter"]);
    row.chosen(0);
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyLyricsClaudeModel];
    openAIKeys = [@{@"api.openai.com": [@"offline-test-key" dataUsingEncoding:NSUTF8StringEncoding]} mutableCopy];
    testKeys = [NSSet setWithArray:@[@"Vitrine.Gemini", @"Vitrine.Claude", @"Vitrine.OpenAI"]];
    CHECK(([SGLyricsAIAvailable() isEqual:@[@0, @1, @2]]));
    NSString *prompt = SGLyricsTranslationPrompt(@[@"A", @""], @"ko");
    NSDictionary *claude = [NSJSONSerialization JSONObjectWithData:SGClaudeRequest(SGLyricsTranslationInstruction(), prompt, &problem).HTTPBody options:0 error:nil];
    CHECK([claude[@"model"] isEqual:@"claude-sonnet-5"] && [claude[@"max_tokens"] isEqual:@8192]);
    CHECK([claude[@"system"] isEqual:SGLyricsTranslationInstruction()] && [claude[@"messages"][0][@"content"] isEqual:prompt]);
    puts("Claude / presets: multipart and fenced replies, errors, bounds, all five endpoints and stored selection passed");
}
static void checkAIJobs(void) {
    NSArray *texts = @[@"Blue robot", @"", @"♪"];
    for (NSInteger notation = 0; notation < 3; notation++) {
        NSString *prompt = SGLyricsAIJobPrompt(@"pronunciation", texts, @"ko", notation);
        CHECK([prompt containsString:@"sound, not the meaning"] && [prompt containsString:@"exactly 3 strings"]);
        CHECK([prompt containsString:(notation == 0 ? @"Korean" : notation == 1 ? @"Latin letters" : @"IPA")]);
        NSString *array = [[prompt componentsSeparatedByString:@"\n\n"] lastObject];
        CHECK([[NSJSONSerialization JSONObjectWithData:[array dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] isEqual:texts]);
    }
    NSString *notes = SGLyricsAIJobPrompt(@"notes", texts, @"ko", 0);
    CHECK([notes containsString:@"Most lines get an empty string"] && [notes containsString:@"140 characters"] && [notes containsString:@"Korean"]);
    CHECK(!SGLyricsAIJobPrompt(@"other", texts, @"en", 0) && !SGLyricsAIJobPrompt(@"pronunciation", texts, @"en", 3));
    CHECK(!SGLyricsAIJobPrompt(@"notes", (id)@[@42], @"en", 0));
    CHECK(([SGLyricsAIJobReply(@"pronunciation", texts, SGLyricsAIArrayIn(@"[\"blu\",\"wrong\",\"wrong\"]", 3)) isEqual:@[@"blu", @"", @""]]));
    CHECK(!SGLyricsAIJobReply(@"notes", texts, SGLyricsAIArrayIn(@"[1,2,3]", 3)));
    CHECK(!SGLyricsAIJobReply(@"notes", texts, @[@"one"]));
    NSString *longNote = [@"a" stringByPaddingToLength:141 withString:@"a" startingAtIndex:0];
    CHECK(!SGLyricsAIJobReply(@"notes", @[@"words"], @[longNote]));
    NSString *accents = [@"é" stringByPaddingToLength:280 withString:@"é" startingAtIndex:0];
    CHECK(SGLyricsAIJobReply(@"notes", @[@"words"], @[accents]));

    testLanguage = @"ko";
    [NSUserDefaults.standardUserDefaults setInteger:1 forKey:SGKeyLyricsPronunciationNotation];
    NSString *problem;
    aiReplies = [NSMutableArray arrayWithObject:claudeReply(@"[\"blu\",\"\",\"\"]")];
    duplicateAIReply = YES;
    CHECK(([askAI(SGLyricsAIClaude, @"claude-job", texts, NO, &problem) isEqual:@[@"blu", @"", @""]] && !problem));
    duplicateAIReply = NO;
    CHECK([lastAIRequest.URL.absoluteString isEqual:@"https://api.anthropic.com/v1/messages"]);
    CHECK([[lastAIRequest valueForHTTPHeaderField:@"x-api-key"] isEqual:@"offline-test-key"]);
    CHECK([[lastAIRequest valueForHTTPHeaderField:@"anthropic-version"] isEqual:@"2023-06-01"]);
    NSUInteger before = aiRequests;
    CHECK(askAI(SGLyricsAIClaude, @"claude-job", texts, NO, &problem) && aiRequests == before);
    CHECK([[SGLyricsSavedAI(@"pronunciation", @"claude-job", @"1") objectForKey:@"Blue robot"] isEqual:@"blu"]);
    SGLyricsAIForgotten();
    CHECK(askAI(SGLyricsAIClaude, @"claude-job", texts, NO, &problem) && aiRequests == before);

    aiReplies = [NSMutableArray arrayWithObject:chatReply(@"[\"A reference.\",\"\",\"\"]")];
    CHECK(askAI(SGLyricsAIOpenAI, @"openai-job", texts, YES, &problem) && !problem);
    CHECK([[lastAIRequest valueForHTTPHeaderField:@"Authorization"] isEqual:@"Bearer offline-test-key"]);
    aiReplies = [NSMutableArray arrayWithObject:@{@"candidates": @[@{@"content": @{@"parts": @[@{@"text": @"[\"A reference.\",\"\",\"\"]"}]}, @"finishReason": @"STOP"}]}];
    CHECK(askAI(SGLyricsAIGemini, @"gemini-job", texts, YES, &problem) && !problem);
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:lastAIRequest.HTTPBody options:0 error:nil];
    CHECK([lastAIRequest.URL.absoluteString containsString:@"gemini-flash-latest:generateContent"]);
    CHECK([[lastAIRequest valueForHTTPHeaderField:@"x-goog-api-key"] isEqual:@"offline-test-key"]);
    CHECK([body[@"generationConfig"][@"responseSchema"][@"items"][@"type"] isEqual:@"STRING"]);
    CHECK([body[@"safetySettings"] count] == 4);
    for (NSDictionary *entry in body[@"safetySettings"]) CHECK([entry[@"threshold"] isEqual:@"BLOCK_NONE"]);
    aiReplies = [NSMutableArray arrayWithObject:@{@"candidates": @[@{@"content": @{@"parts": @[@{@"text": @"[42,\"\",\"\"]"}]}}]}];
    CHECK(!askAI(SGLyricsAIGemini, @"gemini-invalid", texts, YES, &problem) && problem.length);

    __block NSUInteger calls = 0;
    before = aiRequests;
    aiReplies = [NSMutableArray arrayWithObject:claudeReply(@"[\"blu\",\"\",\"\"]")];
    for (NSUInteger i = 0; i < 2; i++) SGLyricsAIPronounce(SGLyricsAIClaude, @"concurrent-job", aiLines(texts), ^(NSArray *answer, NSString *error) {
        CHECK(NSThread.isMainThread && answer.count == 3 && !error); calls++;
    });
    waitFor(^BOOL { return calls == 2; });
    CHECK(aiRequests == before + 1);
    aiReplies = [NSMutableArray arrayWithObject:claudeReply(@"[\"blu\",\"\",\"\"]")];
    beforeAIReply = ^{ SGLyricsDeleteSavedTranslations(); };
    CHECK(askAI(SGLyricsAIClaude, @"deleted-job", texts, NO, &problem));
    beforeAIReply = nil;
    CHECK(!SGLyricsSavedAI(@"pronunciation", @"deleted-job", @"1"));
    testKeys = [NSSet set];
    CHECK(!askAI(SGLyricsAIClaude, @"missing-key", texts, NO, &problem) && [problem containsString:@"key"]);
    CHECK(SGLyricsAIAvailable().count == 0);
    puts("AI jobs: prompt JSON, notation, note limits, all three requests, strict replies, main completion, coalescing and memo passed");
}
static void checkAIStore(void) {
    SGLyricsDeleteSavedTranslations();
    NSDictionary *values = @{@"original": @"value", @"": @"", @"한글 😀": @"기록"};
    SGLyricsSaveAI(@"notes", @"../unsafe/track", @"ko-KR", values);
    CHECK([SGLyricsSavedAI(@"notes", @"../unsafe/track", @"ko-KR") isEqual:values]);
    CHECK(!SGLyricsSavedAI(@"notes", @".._unsafe_track", @"ko-KR"));
    CHECK(!SGLyricsSavedAI(@"pronunciation", @"../unsafe/track", @"ko-KR"));
    CHECK(!SGLyricsSavedAI(@"notes", @"../unsafe/track", @"en"));
    SGLyricsSaveAI(@"notes", @"bad", @"ko", (id)@{@"line": @42});
    CHECK(!SGLyricsSavedAI(@"notes", @"bad", @"ko"));
    SGLyricsSaveAI(@"other", @"bad", @"ko", values);
    CHECK(!SGLyricsSavedAI(@"other", @"bad", @"ko"));
    NSArray *lines = aiLines(@[@"saved line"]);
    ((SGKaraokeLine *)lines[0]).translation = @"저장";
    ((SGKaraokeLine *)lines[0]).translationMade = YES;
    SGLyricsSaveTranslation(@"store-test", @"ko", lines);
    SGLyricsSavedAI(@"notes", @"barrier", @"ko");
    CHECK([SGSavedTranslationsRow().value() hasPrefix:@"2 ·"]);
    NSURL *directory = [SGLyricsTestCacheRoot() URLByAppendingPathComponent:@"AI"];
    NSURL *file = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory includingPropertiesForKeys:nil options:0 error:nil].firstObject;
    [@"{\"bad\":42}" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
    CHECK(!SGLyricsSavedAI(@"notes", @"../unsafe/track", @"ko-KR"));
    SGLyricsDeleteSavedTranslations();
    testLanguage = @"ko";
    SGLyricsSaveAI(@"pronunciation", @"script-zero", @"0", values);
    CHECK([SGLyricsSavedAI(@"pronunciation", @"script-zero", @"0") isEqual:values]);
    testLanguage = @"en";
    CHECK(!SGLyricsSavedAI(@"pronunciation", @"script-zero", @"0"));
    testLanguage = @"ko";
    CHECK([SGLyricsSavedAI(@"pronunciation", @"script-zero", @"0") isEqual:values]);
    SGLyricsDeleteSavedTranslations();
    CHECK([SGSavedTranslationsRow().value() isEqual:@"None"]);
    SGLyricsSaveAI(@"notes", @"ancient", @"ko", values);
    CHECK(SGLyricsSavedAI(@"notes", @"ancient", @"ko"));
    file = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory includingPropertiesForKeys:nil options:0 error:nil].firstObject;
    [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSince1970:1]} ofItemAtPath:file.path error:nil];
    for (NSUInteger i = 0; i < 200; i++) SGLyricsSaveAI(@"notes", [NSString stringWithFormat:@"track-%lu", (unsigned long)i], @"ko", values);
    CHECK([SGLyricsSavedAI(@"notes", @"track-199", @"ko") isEqual:values]);
    CHECK(!SGLyricsSavedAI(@"notes", @"ancient", @"ko"));
    CHECK([NSFileManager.defaultManager contentsOfDirectoryAtURL:directory includingPropertiesForKeys:nil options:0 error:nil].count == 200);
    SGLyricsDeleteSavedTranslations();
    CHECK(!SGLyricsSavedAI(@"notes", @"track-199", @"ko"));
    puts("Saved AI: isolated round trip, empty values, tuple isolation, malformed data, combined count/delete and newest 200 passed");
}
static void checkTranslationReplacement(void) {
    SGLyricsDeleteSavedTranslations();
    NSArray<SGKaraokeLine *> *first = aiLines(@[@"blue robot", @"source-only"]);
    first[0].translation = @"구글 번역"; first[0].translationMade = YES;
    first[1].translation = @"Source translation";
    SGLyricsSaveTranslation(@"switch-service", @"ko", first);
    NSArray<SGKaraokeLine *> *reopened = aiLines(@[@"blue robot", @"source-only"]);
    reopened[1].translation = @"Source translation";
    SGLyricsSyncSavedTranslation(@"switch-service", @"ko", reopened);
    CHECK([reopened[0].translation isEqual:@"구글 번역"] && reopened[0].translationMade);
    CHECK([reopened[1].translation isEqual:@"Source translation"] && !reopened[1].translationMade);
    NSUInteger firstJob = SGLyricsBeginTranslation(@"switch-service", @"ko");
    NSUInteger otherLanguage = SGLyricsBeginTranslation(@"switch-service", @"ja");
    NSUInteger otherTrack = SGLyricsBeginTranslation(@"other-track", @"ko");
    CHECK(firstJob && SGLyricsTranslationIsCurrent(@"switch-service", @"ko", firstJob));
    NSUInteger secondJob = SGLyricsBeginTranslation(@"switch-service", @"ko");
    CHECK(!SGLyricsTranslationIsCurrent(@"switch-service", @"ko", firstJob));
    CHECK(SGLyricsTranslationIsCurrent(@"switch-service", @"ko", secondJob));
    CHECK(SGLyricsTranslationIsCurrent(@"switch-service", @"ja", otherLanguage));
    CHECK(SGLyricsTranslationIsCurrent(@"other-track", @"ko", otherTrack));
    first[0].translation = @"빙 번역";
    SGLyricsSaveTranslation(@"switch-service", @"ko", first);
    SGLyricsSyncSavedTranslation(@"switch-service", @"ko", reopened);
    CHECK([reopened[0].translation isEqual:@"빙 번역"]);
    first[0].translation = @"日本語";
    SGLyricsSaveTranslation(@"switch-service", @"ja", first);
    SGLyricsSyncSavedTranslation(@"switch-service", @"ja", reopened);
    CHECK([reopened[0].translation isEqual:@"日本語"]);
    SGLyricsSaveTranslation(@"other-track", @"ko", first);
    SGLyricsSaveAI(@"notes", @"switch-service", @"ko", @{@"blue robot": @"note"});
    SGLyricsDeleteTranslation(@"switch-service", @"ko");
    CHECK(!SGLyricsTranslationIsCurrent(@"switch-service", @"ko", secondJob));
    CHECK(SGLyricsTranslationIsCurrent(@"switch-service", @"ja", otherLanguage));
    CHECK(SGLyricsTranslationIsCurrent(@"other-track", @"ko", otherTrack));
    SGLyricsSyncSavedTranslation(@"switch-service", @"ko", reopened);
    CHECK(!reopened[0].translation && !reopened[0].translationMade);
    CHECK([reopened[1].translation isEqual:@"Source translation"]);
    SGLyricsSyncSavedTranslation(@"switch-service", @"ja", reopened);
    CHECK([reopened[0].translation isEqual:@"日本語"]);
    SGLyricsSyncSavedTranslation(@"other-track", @"ko", reopened);
    CHECK([reopened[0].translation isEqual:@"日本語"]);
    CHECK([SGLyricsSavedAI(@"notes", @"switch-service", @"ko")[@"blue robot"] isEqual:@"note"]);
    SGLyricsDeleteTranslation(@"../switch-service", @"ko");
    CHECK(!SGLyricsBeginTranslation(nil, @"ko") && !SGLyricsTranslationIsCurrent(@"other-track", @"ko", 0));
    SGLyricsEndTranslation(@"other-track", @"ko", firstJob);
    CHECK(SGLyricsTranslationIsCurrent(@"other-track", @"ko", otherTrack));
    SGLyricsEndTranslation(@"other-track", @"ko", otherTrack);
    CHECK(!SGLyricsTranslationIsCurrent(@"other-track", @"ko", otherTrack));
    SGLyricsDeleteSavedTranslations();
    CHECK(!SGLyricsTranslationIsCurrent(@"switch-service", @"ja", otherLanguage));
    CHECK(!SGLyricsTranslationIsCurrent(@"other-track", @"ko", otherTrack));
    // Force a real filesystem failure: the expected directory is a file. Both current and sibling
    // views still take the latest result in memory; removal and global deletion clear it too.
    NSURL *directory = [SGLyricsTestCacheRoot() URLByAppendingPathComponent:@"Translations"];
    [@"not a directory" writeToURL:directory atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSArray<SGKaraokeLine *> *failed = aiLines(@[@"blue robot"]);
    failed[0].translation = @"메모리 번역"; failed[0].translationMade = YES;
    SGLyricsSaveTranslation(@"disk-failure", @"ko", failed);
    NSArray<SGKaraokeLine *> *sibling = aiLines(@[@"blue robot"]);
    SGLyricsSyncSavedTranslation(@"disk-failure", @"ko", failed);
    SGLyricsSyncSavedTranslation(@"disk-failure", @"ko", sibling);
    CHECK([failed[0].translation isEqual:@"메모리 번역"] && [sibling[0].translation isEqual:@"메모리 번역"]);
    SGLyricsDeleteTranslation(@"disk-failure", @"ko");
    SGLyricsSyncSavedTranslation(@"disk-failure", @"ko", sibling);
    CHECK(!sibling[0].translation);
    SGLyricsSaveTranslation(@"disk-failure", @"ko", failed);
    SGLyricsDeleteSavedTranslations();
    SGLyricsSyncSavedTranslation(@"disk-failure", @"ko", failed);
    CHECK(!failed[0].translation);
    // A local identifier that fit before must keep using its old file, without requiring migration.
    NSString *legacyLocalID = [@"spotify:local:" stringByPaddingToLength:180 withString:@"a" startingAtIndex:0];
    [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *legacyFile = [directory URLByAppendingPathComponent:[legacyLocalID stringByAppendingString:@".ko.json"]];
    NSData *legacyData = [NSJSONSerialization dataWithJSONObject:@{@"blue robot": @"기존 번역"} options:0 error:nil];
    CHECK([legacyData writeToURL:legacyFile atomically:YES]);
    SGLyricsSyncSavedTranslation(legacyLocalID, @"ko", sibling);
    CHECK([sibling[0].translation isEqual:@"기존 번역"]);
    SGLyricsDeleteTranslation(legacyLocalID, @"ko");
    CHECK(![NSFileManager.defaultManager fileExistsAtPath:legacyFile.path]);
    NSString *longLocalID = [@"spotify:local:" stringByAppendingString:[@"한" stringByPaddingToLength:100 withString:@"한" startingAtIndex:0]];
    failed[0].translation = @"긴 제목 번역"; failed[0].translationMade = YES;
    SGLyricsSaveTranslation(longLocalID, @"ko", failed);
    SGLyricsSyncSavedTranslation(longLocalID, @"ko", sibling);
    CHECK([sibling[0].translation isEqual:@"긴 제목 번역"]);
    CHECK([NSFileManager.defaultManager contentsOfDirectoryAtURL:directory includingPropertiesForKeys:nil options:0 error:nil].count == 1);
    SGLyricsDeleteTranslation(longLocalID, @"ko");
    SGLyricsSyncSavedTranslation(longLocalID, @"ko", sibling);
    CHECK(!sibling[0].translation);
    puts("Translation replacement: service/language refresh, scoped deletion, stale-job guards and failed-write retention passed");
}
static void checkTitles(void) {
    CHECK(SGLyricsTitleNeedsTranslation(@"파란 하늘", @"en"));
    CHECK(SGLyricsTitleNeedsTranslation(@"Blue robot", @"ko"));
    CHECK(SGLyricsTitleNeedsTranslation(@"夜空", @"en"));
    CHECK(!SGLyricsTitleNeedsTranslation(@"파란 하늘", @"ko-KR"));
    CHECK(!SGLyricsTitleNeedsTranslation(@"青空", @"ja"));
    CHECK(!SGLyricsTitleNeedsTranslation(@"The blue robot waves hello", @"en-US"));
    CHECK(!SGLyricsTitleNeedsTranslation(@"123 ♪ 😀", @"ko"));
    CHECK(!SGLyricsTitleNeedsTranslation(@"", @"en"));
    CHECK(!SGLyricsTitleNeedsTranslation(@"words", @"en&to=ko"));
    CHECK(SGLyricsTitleLatinArtist(@"Björk & Friends 2") && !SGLyricsTitleLatinArtist(@"한글 Band"));
    CHECK(!SGLyricsTitleLatinArtist(@"夜") && !SGLyricsTitleLatinArtist(@"123"));
    testLanguage = @"ko"; titlesEnabled = deviceAvailable = YES;
    deviceAnswer = @[@"파란 로봇", @"번역된 아티스트"];
    __block NSUInteger notifications = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:SGTranslatedTitleDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        CHECK(NSThread.isMainThread && [note.object isKindOfClass:NSString.class]); notifications++;
    }];
    NSString *artist = @"old";
    CHECK(!SGLyricsTranslatedTitle(@"title-one", @"Blue robot", @"Latin Artist", &artist) && !artist);
    CHECK(!SGLyricsTranslatedTitle(@"title-one", @"Blue robot", @"Latin Artist", NULL));
    waitFor(^BOOL { return notifications == 1; });
    CHECK(deviceCalls == 1);
    CHECK([SGLyricsTranslatedTitle(@"title-one", @"Blue robot", @"Latin Artist", &artist) isEqual:@"파란 로봇"] && [artist isEqual:@"Latin Artist"]);
    titlesEnabled = NO;
    CHECK(!SGLyricsTranslatedTitle(@"title-one", @"Blue robot", @"Latin Artist", &artist) && !artist);
    titlesEnabled = YES;
    CHECK(!SGLyricsTranslatedTitle(@"same-language", @"파란 하늘", @"Artist", NULL) && deviceCalls == 1);
    deviceAnswer = nil;
    testKeys = [NSSet setWithObject:@"Vitrine.Claude"];
    aiReplies = [NSMutableArray arrayWithObject:claudeReply(@"[\"로봇\",\"가수\"]")];
    CHECK(!SGLyricsTranslatedTitle(@"title-fallback", @"Blue robot", @"歌手", NULL));
    waitFor(^BOOL { return notifications == 2; });
    CHECK([SGLyricsTranslatedTitle(@"title-fallback", @"Blue robot", @"歌手", &artist) isEqual:@"로봇"] && [artist isEqual:@"가수"]);
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:lastAIRequest.HTTPBody options:0 error:nil];
    CHECK([body[@"messages"][0][@"content"] containsString:@"exactly 2 strings"]);
    testKeys = [NSSet set];
    deviceAnswer = @[@"로봇", @"가수"];
    for (NSUInteger i = 0; i < 200; i++) SGLyricsTranslatedTitle([NSString stringWithFormat:@"title-cache-%lu", (unsigned long)i], @"Blue robot", @"Artist", NULL);
    waitFor(^BOOL { return notifications == 202; });
    NSUInteger before = deviceCalls;
    CHECK(!SGLyricsTranslatedTitle(@"title-one", @"Blue robot", @"Latin Artist", NULL));
    CHECK(deviceCalls == before);
    CHECK(SGLyricsTranslatedTitle(@"title-cache-199", @"Blue robot", @"Artist", NULL));
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    titlesEnabled = deviceAvailable = NO; testLanguage = nil;
    puts("Titles: language/script detection, Latin artists, two-line request, local fallback, notification, once per track and 200-result cache passed");
}
static void checkNewAI(void) {
    NSArray *keys = @[SGKeyLyricsOpenAIBaseURL, SGKeyLyricsOpenAIModel, SGKeyLyricsClaudeModel, SGKeyLyricsPronunciationNotation];
    NSMutableDictionary *before = [NSMutableDictionary dictionary];
    for (NSString *key in keys) before[key] = [NSUserDefaults.standardUserDefaults objectForKey:key] ?: NSNull.null;
    checkOpenAIHostKeys();
    checkClaudeAndPresets();
    checkAIJobs();
    checkAIStore();
    checkTranslationReplacement();
    checkTitles();
    for (NSString *key in keys) {
        if (before[key] == NSNull.null) [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
        else [NSUserDefaults.standardUserDefaults setObject:before[key] forKey:key];
    }
    SGLyricsDeleteSavedTranslations();
    [NSFileManager.defaultManager removeItemAtURL:SGLyricsTestCacheRoot() error:nil];
}
