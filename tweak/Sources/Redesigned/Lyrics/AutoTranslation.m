#import "Core/SGCore.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "AutoTranslation.h"

NSNotificationName const SGRAutoTranslationDidChangeNotification = @"spotifyglass.redesign.autoTranslationDidChange";
BOOL SGRAutoTranslationEnabled(void) { return SGFlag(SGRKeyLyricsAutoTranslation, NO); }
static NSArray *defaultOrder(void) {
    return @[@(SGRAutoTranslatorOnDevice), @(SGRAutoTranslatorBing), @(SGRAutoTranslatorGoogle),
        @(SGRAutoTranslatorDeepL), @(SGRAutoTranslatorGemini), @(SGRAutoTranslatorClaude),
        @(SGRAutoTranslatorOpenAI), @(SGRAutoTranslatorAppleIntelligence)];
}
static NSArray *validatedOrder(id raw) {
    NSMutableArray *order = [NSMutableArray array];
    if ([raw isKindOfClass:NSArray.class]) for (id value in raw) {
        if ([value isKindOfClass:NSNumber.class] && [defaultOrder() containsObject:value] && ![order containsObject:value]) [order addObject:value];
    }
    for (NSNumber *value in defaultOrder()) if (![order containsObject:value]) [order addObject:value];
    return order;
}
NSArray<NSNumber *> *SGRAutoTranslationOrder(void) {
    return validatedOrder([NSUserDefaults.standardUserDefaults objectForKey:SGRKeyLyricsAutoTranslationOrder]);
}
void SGRSetAutoTranslationOrder(NSArray<NSNumber *> *order) {
    [NSUserDefaults.standardUserDefaults setObject:validatedOrder(order) forKey:SGRKeyLyricsAutoTranslationOrder];
    SGRAutoTranslationSettingsChanged();
}
SGRAutoTranslationState SGRAutoTranslationStateOf(SGRAutoTranslator provider, NSString *language) {
    switch (provider) {
        case SGRAutoTranslatorOnDevice:
            return SGOnDeviceTranslation.translationAvailable ? SGRAutoTranslationReady : SGRAutoTranslationUnavailableDevice;
        case SGRAutoTranslatorAppleIntelligence:
            return [SGOnDeviceTranslation appleIntelligenceAvailable:language] ? SGRAutoTranslationReady : SGRAutoTranslationUnavailableDevice;
        case SGRAutoTranslatorGoogle:
            if (!SGFlag(SGKeyLyricsGoogleTranslate, NO)) return SGRAutoTranslationNeedsSwitch;
            return SGGoogleTargetLanguage(language) ? SGRAutoTranslationReady : SGRAutoTranslationUnsupportedLanguage;
        case SGRAutoTranslatorBing:
            if (!SGFlag(SGKeyLyricsBingTranslate, NO)) return SGRAutoTranslationNeedsSwitch;
            return SGBingTargetLanguage(language) ? SGRAutoTranslationReady : SGRAutoTranslationUnsupportedLanguage;
        case SGRAutoTranslatorDeepL:
            if (!SGDeepLKeySet()) return SGRAutoTranslationNeedsKey;
            return SGDeepLTargetLanguage(language) ? SGRAutoTranslationReady : SGRAutoTranslationUnsupportedLanguage;
        case SGRAutoTranslatorGemini: return SGGeminiKeySet() ? SGRAutoTranslationReady : SGRAutoTranslationNeedsKey;
        case SGRAutoTranslatorClaude: return SGClaudeKeySet() ? SGRAutoTranslationReady : SGRAutoTranslationNeedsKey;
        case SGRAutoTranslatorOpenAI: {
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            NSString *base = [defaults stringForKey:SGKeyLyricsOpenAIBaseURL] ?: @"https://api.openai.com/v1";
            NSString *model = [defaults stringForKey:SGKeyLyricsOpenAIModel] ?: @"gpt-4o-mini";
            if (!SGOpenAICompletionURL(base) || ![model stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length)
                return SGRAutoTranslationNeedsSettings;
            return SGOpenAIKeySet() ? SGRAutoTranslationReady : SGRAutoTranslationNeedsKey;
        }
        default: return SGRAutoTranslationUnavailableDevice;
    }
}
BOOL SGRAutoTranslationAvailable(SGRAutoTranslator provider, NSString *language) {
    return language.length && SGRAutoTranslationStateOf(provider, language) == SGRAutoTranslationReady;
}

// All bookkeeping is on main. Automatic work shares the manual translator's tokens, so removing a
// translation or starting a manual replacement makes an older automatic answer harmless.
static NSUInteger revision = 1;
static NSArray *configuration;
static NSMutableOrderedSet<NSArray *> *attempted, *suppressed, *freshRetries;
static NSMutableDictionary<NSArray *, NSNumber *> *active;
@interface SGRAutoTranslationProgress ()
@property (nonatomic) SGRAutoTranslationPhase phase;
@property (nonatomic) SGRAutoTranslator provider;
@property (nonatomic) SGRAutoTranslationFailure failure;
@property (nonatomic) NSUInteger completed, total, attempt;
@end
@implementation SGRAutoTranslationProgress
@end
NSNotificationName const SGRAutoTranslationProgressDidChangeNotification = @"spotifyglass.redesign.autoTranslationProgressDidChange";
static NSMutableDictionary<NSArray *, SGRAutoTranslationProgress *> *statuses;
static NSMutableOrderedSet<NSArray *> *statusOrder;
static void statusChanged(NSArray *pair) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGRAutoTranslationProgressDidChangeNotification
        object:pair.firstObject userInfo:pair ? @{@"language": pair[1]} : nil];
}
static void clearStatus(NSArray *pair) {
    if (!statuses[pair]) return;
    [statuses removeObjectForKey:pair]; [statusOrder removeObject:pair]; statusChanged(pair);
}
static void publishStatus(NSArray *pair, SGRAutoTranslationPhase phase, SGRAutoTranslator provider,
                          SGRAutoTranslationFailure failure, NSUInteger completed, NSUInteger total, NSUInteger attempt) {
    SGRAutoTranslationProgress *old = statuses[pair];
    if (old && old.phase == phase && old.provider == provider && old.failure == failure &&
        old.completed == completed && old.total == total && old.attempt == attempt) return;
    SGRAutoTranslationProgress *snapshot = [SGRAutoTranslationProgress new];
    snapshot.phase = phase; snapshot.provider = provider; snapshot.failure = failure;
    snapshot.completed = completed; snapshot.total = total; snapshot.attempt = attempt;
    if (!old && statusOrder.count >= 200) { [statuses removeObjectForKey:statusOrder.firstObject]; [statusOrder removeObjectAtIndex:0]; }
    statuses[pair] = snapshot; [statusOrder removeObject:pair]; [statusOrder addObject:pair]; statusChanged(pair);
}
// Match only known local messages. Untrusted server bodies are never exposed as status text.
static SGRAutoTranslationFailure failureOf(NSString *problem) {
    NSArray *connection = @[
        SGL(@"settings.translation.openai.error.unreachable", @"The translation service could not be reached."),
        SGL(@"settings.translation.error.unreachable", @"Gemini could not be reached."),
        SGL(@"settings.translation.deepl.error.unreachable", @"DeepL could not be reached."),
        SGL(@"settings.translation.google.error.unreachable", @"Google Translate could not be reached."),
        SGL(@"settings.translation.bing.error.unreachable", @"Bing Translator could not be reached."),
        SGL(@"settings.translation.claude.error.unreachable", @"Claude could not be reached.")];
    if (problem && [connection containsObject:problem]) return SGRAutoTranslationFailureConnection;
    NSArray *authentication = @[
        SGL(@"settings.translation.openai.error.keyinvalid", @"The translation service turned the key down. Check it on the Lyrics page."),
        SGL(@"settings.translation.error.keyinvalid", @"Gemini turned the key down. Check it on the Lyrics page."),
        SGL(@"settings.translation.deepl.error.keyinvalid", @"DeepL turned the key down. Check it on the Lyrics page."),
        SGL(@"settings.translation.claude.error.keyinvalid", @"Claude turned the key down. Check it on the Lyrics page.")];
    if (problem && [authentication containsObject:problem]) return SGRAutoTranslationFailureAuthentication;
    NSArray *busy = @[
        SGL(@"settings.translation.openai.error.busy", @"The translation service is busy right now. Try again in a minute."),
        SGL(@"settings.translation.error.busy", @"Gemini is busy right now. Try again in a minute."),
        SGL(@"settings.translation.error.ratelimit", @"Gemini's limit for this key is reached for now."),
        SGL(@"settings.translation.deepl.error.busy", @"DeepL is busy right now. Try again in a minute."),
        SGL(@"settings.translation.deepl.error.quota", @"This DeepL key's translation quota is used up."),
        SGL(@"settings.translation.google.error.busy", @"Google Translate is busy right now. Try again in a minute."),
        SGL(@"settings.translation.bing.error.busy", @"Bing Translator is busy right now. Try again in a minute."),
        SGL(@"settings.translation.claude.error.busy", @"Claude is busy right now. Try again in a minute.")];
    return problem && [busy containsObject:problem] ? SGRAutoTranslationFailureBusy : SGRAutoTranslationFailureResponse;
}
static NSArray *currentConfiguration(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *language = SGLyricsGeminiLanguage();
    NSMutableArray *states = [NSMutableArray array];
    for (NSNumber *provider in SGRAutoTranslationOrder()) [states addObject:@(SGRAutoTranslationStateOf(provider.integerValue, language))];
    return @[@(SGRAutoTranslationEnabled()), SGRAutoTranslationOrder(), language ?: @"", states,
        @(SGFlag(SGKeyLyricsTranslateEverySong, NO)),
        [defaults stringForKey:SGKeyLyricsOpenAIBaseURL] ?: @"", [defaults stringForKey:SGKeyLyricsOpenAIModel] ?: @"",
        [defaults stringForKey:SGKeyLyricsClaudeModel] ?: @""];

}
static void remember(NSMutableOrderedSet *set, NSArray *pair) {
    if ([set containsObject:pair]) return;
    if (set.count >= 2000) [set removeObjectAtIndex:0];
    [set addObject:pair];
}
static void invalidate(BOOL explicitSelection) {
    for (NSArray *pair in active) SGLyricsEndTranslation(pair[0], pair[1], active[pair].unsignedIntegerValue);
    [active removeAllObjects];
    [attempted removeAllObjects]; [freshRetries removeAllObjects];
    [statuses removeAllObjects]; [statusOrder removeAllObjects]; statusChanged(nil);
    if (explicitSelection) [suppressed removeAllObjects];
    revision++;
    configuration = currentConfiguration();
    [NSNotificationCenter.defaultCenter postNotificationName:SGRAutoTranslationDidChangeNotification object:nil];
}
static void prepare(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        attempted = [NSMutableOrderedSet orderedSet]; suppressed = [NSMutableOrderedSet orderedSet]; active = [NSMutableDictionary dictionary];
        freshRetries = [NSMutableOrderedSet orderedSet];
        statuses = [NSMutableDictionary dictionary]; statusOrder = [NSMutableOrderedSet orderedSet];
        configuration = currentConfiguration();
        for (NSNotificationName name in @[SGLyricsTranslationsDidChangeNotification, SGLyricsTranslationServiceSettingsDidChangeNotification]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
                // Generic redraws include cultural-note visibility. Only changed translation configuration
                // or an explicit credential/provider update may restart a failed or in-flight chain.
                void (^changed)(void) = ^{
                    if ([note.name isEqual:SGLyricsTranslationServiceSettingsDidChangeNotification] ||
                        ![configuration isEqual:currentConfiguration()]) invalidate(NO);
                };
                if (NSThread.isMainThread) changed(); else dispatch_async(dispatch_get_main_queue(), changed);
            }];
        }
        [NSNotificationCenter.defaultCenter addObserverForName:SGLyricsAIResultDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            if (note.object) return; // A nil object means the combined saved-results store was cleared.
            void (^clear)(void) = ^{
                for (NSArray *pair in active) remember(suppressed, pair);
                NSString *track = SGKaraokePlayingTrack(), *language = SGLyricsGeminiLanguage();
                if (track.length && language.length) remember(suppressed, @[track, language]);
                invalidate(NO);
            };
            if (NSThread.isMainThread) clear(); else dispatch_async(dispatch_get_main_queue(), clear);
        }];
    });
}
NSUInteger SGRAutoTranslationRevision(void) {
    prepare();
    if (![configuration isEqual:currentConfiguration()]) invalidate(NO);
    return revision;
}
void SGRAutoTranslationSettingsChanged(void) { prepare(); invalidate(YES); }
NSUInteger SGRAutoTranslationClaim(NSString *track, NSString *language) {
    NSUInteger current = SGRAutoTranslationRevision();
    if (!track.length || !language.length) return 0;
    NSArray *pair = @[track, language];
    if ([attempted containsObject:pair] || [suppressed containsObject:pair]) return 0;
    remember(attempted, pair);
    return current;
}
void SGRAutoTranslationSuppress(NSString *track, NSString *language) {
    prepare();
    if (!track.length || !language.length) return;
    NSArray *pair = @[track, language];
    remember(suppressed, pair);
    [freshRetries removeObject:pair];
    clearStatus(pair);
    SGLyricsEndTranslation(track, language, active[pair].unsignedIntegerValue);
    [active removeObjectForKey:pair];
}
void SGRAutoTranslationRegister(NSString *track, NSString *language, NSUInteger token) {
    if (token) active[@[track, language]] = @(token);
}
void SGRAutoTranslationFinish(NSString *track, NSString *language, NSUInteger token) {
    NSArray *pair = @[track, language];
    if ([active[pair] isEqual:@(token)]) [active removeObjectForKey:pair];
}
SGRAutoTranslationProgress *SGRAutoTranslationProgressFor(NSString *track, NSString *language) {
    if (!track.length || !language.length) return nil;
    prepare();
    return statuses[@[track, language]];
}
BOOL SGRAutoTranslationRetry(NSString *track, NSString *language) {
    if (!track.length || !language.length) return NO;
    prepare();
    NSArray *pair = @[track, language];
    SGRAutoTranslationProgress *status = statuses[pair];
    if (!status || status.phase == SGRAutoTranslationPhaseRunning || status.phase == SGRAutoTranslationPhaseComplete || active[pair]) return NO;
    [attempted removeObject:pair]; [suppressed removeObject:pair]; remember(freshRetries, pair); clearStatus(pair);
    return YES;
}
void SGRAutoTranslationUnavailable(NSString *track, NSString *language) {
    if (!track.length || !language.length) return;
    prepare();
    NSArray *pair = @[track, language];
    if ([suppressed containsObject:pair] || active[pair]) return;
    publishStatus(pair, SGRAutoTranslationPhaseUnavailable, SGRAutoTranslatorOff, SGRAutoTranslationFailureNone, 0, 0, 0);
}
static void translateUsing(SGRAutoTranslator provider, NSArray<SGKaraokeLine *> *lines, NSString *track,
                      NSString *language, BOOL fresh, SGRAutoTranslated progress, SGRAutoTranslated done) {
    if (!SGRAutoTranslationAvailable(provider, language)) { done(nil, nil); return; }
    NSMutableArray *texts = [NSMutableArray arrayWithCapacity:lines.count];
    for (SGKaraokeLine *line in lines) [texts addObject:SGKaraokeLineText(line) ?: @""];
    // A nil cache identity is already supported by every remote translator. Explicit Retry must not
    // replay a cached partial answer; ordinary automatic attempts keep using their normal memo.
    NSString *cacheTrack = fresh ? nil : track;
    switch (provider) {
        case SGRAutoTranslatorOnDevice: [SGOnDeviceTranslation translate:texts to:language done:done]; break;
        case SGRAutoTranslatorAppleIntelligence: {
            [SGOnDeviceTranslation translateWithAppleIntelligence:texts to:language song:SGLyricsSongName(track)
                progress:^(NSArray *answer) { progress(answer, nil); } done:done]; break;
        }
        case SGRAutoTranslatorGoogle: SGLyricsTranslateWithGoogle(cacheTrack, lines, language, done); break;
        case SGRAutoTranslatorBing: SGLyricsTranslateWithBing(cacheTrack, lines, language, done); break;
        case SGRAutoTranslatorDeepL: SGLyricsTranslateWithDeepL(cacheTrack, lines, language, done); break;
        case SGRAutoTranslatorGemini: SGLyricsTranslateWithGemini(cacheTrack, lines, language, done); break;
        case SGRAutoTranslatorClaude: SGLyricsTranslateWithClaude(cacheTrack, lines, language, done); break;
        case SGRAutoTranslatorOpenAI: SGLyricsTranslateWithOpenAI(cacheTrack, lines, language, done); break;
        default: done(nil, nil); break;
    }
}


// One chain per shared token. Later providers fill only gaps, never overwrite a saved/source/earlier result.
@interface SGRAutoTranslationJob : NSObject
@property (nonatomic, copy) NSString *track, *language;
@property (nonatomic, copy) NSArray<SGKaraokeLine *> *lines;
@property (nonatomic, copy) NSArray<NSNumber *> *order;
@property (nonatomic, strong) NSMutableArray<NSString *> *answer;
@property (nonatomic, strong) NSMutableIndexSet *missing;
@property (nonatomic) NSUInteger revision, next, step, total, token;
@property (nonatomic) SGRAutoTranslator provider;
@property (nonatomic) SGRAutoTranslationFailure failure;
@property (nonatomic) BOOL interrupted, fresh;
@property (nonatomic) BOOL finished;
@property (nonatomic, copy) SGRAutoTranslated progress, done;
@property (nonatomic, copy) BOOL (^mayContinue)(void);
@end
@implementation SGRAutoTranslationJob
- (BOOL)current {
    if (self.finished || SGRAutoTranslationRevision() != self.revision) return NO;
    NSNumber *token = active[@[self.track, self.language]];
    return token && SGLyricsTranslationIsCurrent(self.track, self.language, token.unsignedIntegerValue);
}
- (void)finish:(BOOL)cancelled {
    if (self.finished) return;
    self.finished = YES;
    NSArray *pair = @[self.track, self.language];
    // The old chain may finish after a replacement; it must never clear or overwrite the new status.
    if ([active[pair] isEqual:@(self.token)] && revision == self.revision) {
        if (cancelled) clearStatus(pair);
        else {
            SGRAutoTranslationPhase phase = !self.missing.count ? SGRAutoTranslationPhaseComplete : self.interrupted ? SGRAutoTranslationPhasePaused :
                self.missing.count < self.total ? SGRAutoTranslationPhasePartial : SGRAutoTranslationPhaseFailed;
            publishStatus(pair, phase, self.provider, self.failure, self.total - self.missing.count, self.total, self.step);
        }
    }
    BOOL any = NO;
    for (NSString *text in self.answer) any = any || text.length;
    SGRAutoTranslated done = self.done;
    self.done = nil; self.progress = nil;
    done(!cancelled && any ? [self.answer copy] : nil, nil);
}
- (void)take:(NSArray *)values {
    if (![values isKindOfClass:NSArray.class] || values.count != self.answer.count) return;
    NSMutableIndexSet *filled = [NSMutableIndexSet indexSet];
    [self.missing enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        id text = values[i];
        if ([text isKindOfClass:NSString.class] && [text length] <= 64000 &&
            [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) {
            self.answer[i] = text;
            [filled addIndex:i];
        }
    }];
    [self.missing removeIndexes:filled];
    if (filled.count) {
        publishStatus(@[self.track, self.language], SGRAutoTranslationPhaseRunning, self.provider,
            SGRAutoTranslationFailureNone, self.total - self.missing.count, self.total, self.step);
        self.progress([self.answer copy], nil);
    }
}
- (void)runNext {
    if (![self current]) { [self finish:YES]; return; }
    if (!self.missing.count) { [self finish:NO]; return; }
    if (!self.mayContinue()) { self.interrupted = YES; [self finish:NO]; return; }
    SGRAutoTranslator provider = SGRAutoTranslatorOff;
    while (self.next < self.order.count) {
        SGRAutoTranslator candidate = self.order[self.next++].integerValue;
        if (SGRAutoTranslationAvailable(candidate, self.language)) { provider = candidate; break; }
    }
    if (provider == SGRAutoTranslatorOff) { [self finish:NO]; return; }
    NSUInteger step = ++self.step;
    self.provider = provider;
    publishStatus(@[self.track, self.language], SGRAutoTranslationPhaseRunning, provider, SGRAutoTranslationFailureNone,
        self.total - self.missing.count, self.total, step);
    if (![self current]) { [self finish:YES]; return; }
    if (!self.mayContinue()) { self.interrupted = YES; [self finish:NO]; return; }
    __block BOOL answered = NO;
    translateUsing(provider, self.lines, self.track, self.language, self.fresh, ^(NSArray *values, NSString *error) {
        if (!answered && self.step == step && [self current]) [self take:values];
    }, ^(NSArray *values, NSString *error) {
        if (answered || self.step != step || self.finished) return;
        answered = YES;
        if (![self current]) { [self finish:YES]; return; }
        [self take:values];
        if (self.missing.count) self.failure = failureOf(error);
        dispatch_async(dispatch_get_main_queue(), ^{ [self runNext]; });
    });
}
@end
void SGRAutoTranslateInOrder(NSArray<SGKaraokeLine *> *lines, NSString *track, NSString *language,
                             NSUInteger revision, BOOL (^mayContinue)(void), SGRAutoTranslated progress, SGRAutoTranslated done) {
    SGRAutoTranslationJob *job = [SGRAutoTranslationJob new];
    job.track = track; job.language = language; job.revision = revision; job.token = active[@[track, language]].unsignedIntegerValue;
    NSArray *pair = @[track, language];
    job.fresh = [freshRetries containsObject:pair]; [freshRetries removeObject:pair];
    job.order = SGRAutoTranslationOrder(); job.progress = progress; job.done = done; job.mayContinue = mayContinue;
    job.answer = [NSMutableArray array]; job.missing = [NSMutableIndexSet indexSet];
    NSMutableArray *copies = [NSMutableArray array];
    [lines enumerateObjectsUsingBlock:^(SGKaraokeLine *line, NSUInteger i, BOOL *stop) {
        [copies addObject:[line copy]];
        [job.answer addObject:@""];
        if (!line.translation.length && [SGKaraokeLineText(line) rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location != NSNotFound)
            [job.missing addIndex:i];
    }];
    job.lines = copies; job.total = job.missing.count;
    [job runNext];
}
