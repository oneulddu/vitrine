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
static NSMutableOrderedSet<NSArray *> *attempted, *suppressed;
static NSMutableDictionary<NSArray *, NSNumber *> *active;
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
    [attempted removeAllObjects];
    if (explicitSelection) [suppressed removeAllObjects];
    revision++;
    configuration = currentConfiguration();
    [NSNotificationCenter.defaultCenter postNotificationName:SGRAutoTranslationDidChangeNotification object:nil];
}
static void prepare(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        attempted = [NSMutableOrderedSet orderedSet]; suppressed = [NSMutableOrderedSet orderedSet]; active = [NSMutableDictionary dictionary];
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
static void translateUsing(SGRAutoTranslator provider, NSArray<SGKaraokeLine *> *lines, NSString *track,
                      NSString *language, SGRAutoTranslated progress, SGRAutoTranslated done) {
    if (!SGRAutoTranslationAvailable(provider, language)) { done(nil, nil); return; }
    NSMutableArray *texts = [NSMutableArray arrayWithCapacity:lines.count];
    for (SGKaraokeLine *line in lines) [texts addObject:SGKaraokeLineText(line) ?: @""];
    switch (provider) {
        case SGRAutoTranslatorOnDevice: [SGOnDeviceTranslation translate:texts to:language done:done]; break;
        case SGRAutoTranslatorAppleIntelligence: {
            [SGOnDeviceTranslation translateWithAppleIntelligence:texts to:language song:SGLyricsSongName(track)
                progress:^(NSArray *answer) { progress(answer, nil); } done:done]; break;
        }
        case SGRAutoTranslatorGoogle: SGLyricsTranslateWithGoogle(track, lines, language, done); break;
        case SGRAutoTranslatorBing: SGLyricsTranslateWithBing(track, lines, language, done); break;
        case SGRAutoTranslatorDeepL: SGLyricsTranslateWithDeepL(track, lines, language, done); break;
        case SGRAutoTranslatorGemini: SGLyricsTranslateWithGemini(track, lines, language, done); break;
        case SGRAutoTranslatorClaude: SGLyricsTranslateWithClaude(track, lines, language, done); break;
        case SGRAutoTranslatorOpenAI: SGLyricsTranslateWithOpenAI(track, lines, language, done); break;
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
@property (nonatomic) NSUInteger revision, next, step;
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
    if (filled.count) self.progress([self.answer copy], nil);
}
- (void)runNext {
    if (![self current]) { [self finish:YES]; return; }
    if (!self.missing.count || !self.mayContinue()) { [self finish:NO]; return; }
    SGRAutoTranslator provider = SGRAutoTranslatorOff;
    while (self.next < self.order.count) {
        SGRAutoTranslator candidate = self.order[self.next++].integerValue;
        if (SGRAutoTranslationAvailable(candidate, self.language)) { provider = candidate; break; }
    }
    if (provider == SGRAutoTranslatorOff) { [self finish:NO]; return; }
    NSUInteger step = ++self.step;
    __block BOOL answered = NO;
    translateUsing(provider, self.lines, self.track, self.language, ^(NSArray *values, NSString *error) {
        if (!answered && self.step == step && [self current]) [self take:values];
    }, ^(NSArray *values, NSString *error) {
        if (answered || self.step != step || self.finished) return;
        answered = YES;
        if (![self current]) { [self finish:YES]; return; }
        [self take:values];
        dispatch_async(dispatch_get_main_queue(), ^{ [self runNext]; });
    });
}
@end
void SGRAutoTranslateInOrder(NSArray<SGKaraokeLine *> *lines, NSString *track, NSString *language,
                             NSUInteger revision, BOOL (^mayContinue)(void), SGRAutoTranslated progress, SGRAutoTranslated done) {
    SGRAutoTranslationJob *job = [SGRAutoTranslationJob new];
    job.track = track; job.language = language; job.revision = revision;
    job.order = SGRAutoTranslationOrder(); job.progress = progress; job.done = done; job.mayContinue = mayContinue;
    job.answer = [NSMutableArray array]; job.missing = [NSMutableIndexSet indexSet];
    NSMutableArray *copies = [NSMutableArray array];
    [lines enumerateObjectsUsingBlock:^(SGKaraokeLine *line, NSUInteger i, BOOL *stop) {
        [copies addObject:[line copy]];
        [job.answer addObject:@""];
        if (!line.translation.length && [SGKaraokeLineText(line) rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location != NSNotFound)
            [job.missing addIndex:i];
    }];
    job.lines = copies;
    [job runNext];
}
