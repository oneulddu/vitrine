// Actual automatic chain + actual OpenAI provider memo/parser; only HTTP and credentials are fixtures.
static id autoRetryReply(NSArray *values) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:values options:0 error:nil];
    return chatReply([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
}
static NSArray *autoRetryProvider(NSString *track, NSArray *lines) {
    __block NSUInteger calls = 0; __block NSArray *result;
    SGLyricsTranslateWithOpenAI(track, lines, @"ko", ^(NSArray *answer, NSString *error) {
        CHECK(NSThread.isMainThread && ++calls == 1 && !error); result = answer;
    });
    waitFor(^BOOL { return calls == 1; }); return result;
}
static NSArray *autoRetryChain(NSString *track, NSArray *lines) {
    NSUInteger revision = SGRAutoTranslationClaim(track, @"ko"); CHECK(revision);
    NSUInteger token = SGLyricsBeginTranslation(track, @"ko"); CHECK(token);
    SGRAutoTranslationRegister(track, @"ko", token);
    __block NSUInteger calls = 0; __block NSArray *result;
    SGRAutoTranslateInOrder(lines, track, @"ko", revision, ^BOOL { return YES; }, ^(NSArray *answer, NSString *error) {
        CHECK(NSThread.isMainThread && !error && answer.count == lines.count);
        CHECK(![answer[0] length]); // Existing translation is never returned as a replacement.
    }, ^(NSArray *answer, NSString *error) {
        CHECK(NSThread.isMainThread && ++calls == 1 && !error); result = answer;
        SGRAutoTranslationFinish(track, @"ko", token);
        SGLyricsEndTranslation(track, @"ko", token);
    });
    waitFor(^BOOL { return calls == 1; }); return result;
}
static void checkAutoRetry(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSArray *keys = @[SGKeyLyricsOpenAIBaseURL, SGKeyLyricsOpenAIModel, SGRKeyLyricsAutoTranslationOrder];
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    for (NSString *key in keys) saved[key] = [defaults objectForKey:key] ?: NSNull.null;
    NSSet *savedKeys = testKeys; NSMutableDictionary *savedCredentials = openAIKeys;
    NSString *savedLanguage = testLanguage;
    BOOL savedBing = bingEnabled, savedDevice = deviceAvailable, savedAuto = autoRetryEnabled;
    CHECK(!beforeAIReply && !duplicateAIReply && !keyReadFailure && !keyWriteFailure && !keyDeleteFailure);
    testLanguage = @"ko"; bingEnabled = deviceAvailable = NO; autoRetryEnabled = YES;
    testKeys = [NSSet setWithObject:@"Vitrine.OpenAI"];
    openAIKeys = [@{@"api.openai.com": [@"offline-retry-fixture" dataUsingEncoding:NSUTF8StringEncoding]} mutableCopy];
    [defaults setObject:@"https://api.openai.com/v1" forKey:SGKeyLyricsOpenAIBaseURL];
    [defaults setObject:@"offline-retry-model" forKey:SGKeyLyricsOpenAIModel];
    [defaults setObject:@[@(SGRAutoTranslatorOpenAI)] forKey:SGRKeyLyricsAutoTranslationOrder];
    SGRAutoTranslationSettingsChanged();
    CHECK(SGRAutoTranslationEnabled() && SGRAutoTranslationAvailable(SGRAutoTranslatorOpenAI, @"ko"));
    for (NSInteger provider = 1; provider < SGRAutoTranslatorCount; provider++)
        if (provider != SGRAutoTranslatorOpenAI) CHECK(!SGRAutoTranslationAvailable(provider, @"ko"));
    NSUInteger allBefore = aiRequests;
    for (NSNumber *partial in @[@YES, @NO]) {
        NSString *track = [@"retry-provider-regression-" stringByAppendingString:partial.boolValue ? @"partial" : @"empty"];
        NSString *other = [track stringByAppendingString:@"-other"];
        NSArray *texts = @[@"Already translated source", @"Blue robot", @"Green robot"];
        NSArray<SGKaraokeLine *> *lines = aiLines(texts); lines[0].translation = @"keep existing translation";
        NSArray *incomplete = @[@"must not replace existing", partial.boolValue ? @"first translation" : @"", @""];
        aiReplies = [@[autoRetryReply(incomplete)] mutableCopy];
        NSUInteger before = aiRequests;
        NSArray *first = autoRetryChain(track, lines);
        SGRAutoTranslationProgress *status = SGRAutoTranslationProgressFor(track, @"ko");
        CHECK(aiRequests == before + 1 && !aiReplies.count);
        CHECK(status.provider == SGRAutoTranslatorOpenAI && status.total == 2 && status.completed == partial.unsignedIntegerValue);
        CHECK(status.phase == (partial.boolValue ? SGRAutoTranslationPhasePartial : SGRAutoTranslationPhaseFailed));
        CHECK(partial.boolValue ? ([first[1] isEqual:@"first translation"] && ![first[2] length]) : !first);
        CHECK([lines[0].translation isEqual:@"keep existing translation"]);
        // Prove the real provider cached this incomplete response before invoking Retry.
        CHECK([autoRetryProvider(track, lines) isEqual:incomplete] && aiRequests == before + 1);
        CHECK(!SGRAutoTranslationClaim(track, @"ko"));
        // A second identity already has a provider memo. Retry must not globally disable/clear it.
        NSArray<SGKaraokeLine *> *otherLines = aiLines(texts); otherLines[0].translation = @"other existing";
        aiReplies = [@[autoRetryReply(@[@"ignore", @"other first", @"other second"])] mutableCopy];
        CHECK(autoRetryProvider(other, otherLines).count == 3 && aiRequests == before + 2);
        NSUInteger atRetry = aiRequests;
        CHECK(SGRAutoTranslationRetry(track, @"ko") && !SGRAutoTranslationProgressFor(track, @"ko"));
        CHECK(aiRequests == atRetry); // Retry only clears/rearms this pair; it does not send on its own.
        CHECK([autoRetryChain(other, otherLines)[2] isEqual:@"other second"] && aiRequests == atRetry);
        CHECK(SGRAutoTranslationProgressFor(other, @"ko").phase == SGRAutoTranslationPhaseComplete);
        // Model the view retaining the first attempt's successful line before asking for its gaps.
        if (partial.boolValue) lines[1].translation = first[1];
        aiReplies = [@[autoRetryReply(@[@"overwrite attempt", @"fresh first", @"fresh second"])] mutableCopy];
        NSArray *retried = autoRetryChain(track, lines);
        CHECK(aiRequests == atRetry + 1 && !aiReplies.count); // Fails with the old cached-answer behavior.
        status = SGRAutoTranslationProgressFor(track, @"ko");
        CHECK(status.phase == SGRAutoTranslationPhaseComplete && status.provider == SGRAutoTranslatorOpenAI);
        CHECK(status.completed == status.total && status.total == (partial.boolValue ? 1 : 2));
        CHECK(![retried[0] length] && [lines[0].translation isEqual:@"keep existing translation"]);
        CHECK([retried[2] isEqual:@"fresh second"]);
        if (partial.boolValue) CHECK(![retried[1] length] && [lines[1].translation isEqual:@"first translation"]);
        else CHECK([retried[1] isEqual:@"fresh first"]);
        CHECK(!SGRAutoTranslationRetry(track, @"ko"));
        CHECK([autoRetryProvider(other, otherLines)[2] isEqual:@"other second"] && aiRequests == atRetry + 1);
        // The nil identity bypasses cache writes too; normal calls still use the original memo.
        CHECK([autoRetryProvider(track, lines) isEqual:incomplete] && aiRequests == atRetry + 1);
        SGRAutoTranslationSettingsChanged();
        NSArray<SGKaraokeLine *> *ordinary = aiLines(texts); ordinary[0].translation = @"keep existing translation";
        autoRetryChain(track, ordinary);
        CHECK(aiRequests == atRetry + 1 && SGRAutoTranslationProgressFor(track, @"ko").phase ==
              (partial.boolValue ? SGRAutoTranslationPhasePartial : SGRAutoTranslationPhaseFailed));
        SGRAutoTranslationSettingsChanged();
    }
    CHECK(aiRequests == allBefore + 6);
    for (NSString *key in keys) { if (saved[key] == NSNull.null) [defaults removeObjectForKey:key]; else [defaults setObject:saved[key] forKey:key]; }
    testKeys = savedKeys; openAIKeys = savedCredentials; testLanguage = savedLanguage;
    bingEnabled = savedBing; deviceAvailable = savedDevice; autoRetryEnabled = savedAuto; aiReplies = nil;
    SGRAutoTranslationSettingsChanged();
    puts("Auto Retry: real OpenAI partial/empty memo bypassed once, fresh request completes, other-track cache and existing translations preserved");
}
