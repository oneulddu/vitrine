// A song's language and the choices that follow it, shared by both looks.
#import "Lyrics.h"
#import "LyricsLanguage.h"
#import <NaturalLanguage/NaturalLanguage.h>

NSNotificationName const SGLyricsLanguageDidChangeNotification = @"spotifyglass.lyrics.languageDidChange";
NSNotificationName const SGSimplifyTitlesDidChangeNotification = @"spotifyglass.simplifyTitlesDidChange";

static NSString *languageTag(id tag) {
    if (![tag isKindOfClass:NSString.class] || ![tag length] || [tag length] > 64) return nil;
    if ([tag rangeOfString:@"^[A-Za-z]{2,8}([_-][A-Za-z0-9]{1,8})*$" options:NSRegularExpressionSearch].location == NSNotFound) return nil;
    return [[tag stringByReplacingOccurrencesOfString:@"_" withString:@"-"] lowercaseString];
}

static NSString *baseLanguage(NSString *tag) {
    return [languageTag(tag) componentsSeparatedByString:@"-"].firstObject;
}

NSArray<SGKaraokeLine *> *SGLyricsLanguageSnapshot(NSArray<SGKaraokeLine *> *lines) {
    NSMutableArray *snapshot = [NSMutableArray arrayWithCapacity:lines.count];
    for (SGKaraokeLine *line in lines) {
        SGKaraokeLine *copy = [SGKaraokeLine new];
        NSMutableArray *words = [NSMutableArray arrayWithCapacity:line.words.count];
        for (SGKaraokeWord *word in line.words) {
            SGKaraokeWord *value = [SGKaraokeWord new];
            value.text = [word.text copy];
            value.joined = word.joined;
            [words addObject:value];
        }
        copy.words = [words copy];
        [snapshot addObject:copy];
    }
    return [snapshot copy];
}

static NSArray *languageKey(NSArray<SGKaraokeLine *> *lines) {
    NSMutableArray *key = [NSMutableArray arrayWithCapacity:lines.count];
    for (SGKaraokeLine *line in lines) [key addObject:[SGKaraokeLineText(line) copy] ?: @""];
    return [key copy];
}

static NSCache *languageCache(void) {
    static NSCache *kept;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ kept = [NSCache new]; kept.countLimit = SGLyricsLanguageCacheSongLimit; });
    return kept;
}

NSString *SGLyricsDetectedLanguage(NSArray<SGKaraokeLine *> *lines) {
    if (!lines.count) return nil;
    NSArray *key = languageKey(lines);
    NSCache *kept = languageCache();
    NSString *cached = [kept objectForKey:key];
    if (cached) return cached.length ? cached : nil;
    if (SGLyricsLooksJapanese(lines)) {
        [kept setObject:@"ja" forKey:key];
        return @"ja";
    }
    NLLanguageRecognizer *recognizer = [NLLanguageRecognizer new];
    NSMutableSet *seen = [NSMutableSet set];
    NSMutableDictionary<NSString *, NSNumber *> *weights = [NSMutableDictionary dictionary];
    double total = 0;
    for (SGKaraokeLine *line in lines) {
        NSString *text = [SGKaraokeLineText(line) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([seen containsObject:text] || [text rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location == NSNotFound) continue;
        [seen addObject:text];
        [recognizer reset];
        [recognizer processString:text];
        NSDictionary<NLLanguage, NSNumber *> *guesses = [recognizer languageHypothesesWithMaximum:1];
        NSString *tag = guesses.allKeys.firstObject;
        double confidence = [guesses[tag ?: @""] doubleValue];
        total += text.length;
        NSString *language = baseLanguage(tag);
        if (confidence >= 0.6 && language.length && ![language isEqualToString:@"und"])
            weights[language] = @([weights[language] doubleValue] + text.length * confidence);
    }
    NSString *best;
    double highest = 0;
    for (NSString *language in weights) {
        double weight = weights[language].doubleValue;
        if (weight > highest) { highest = weight; best = language; }
    }
    // Short or divided lines should not silently impose another language's display choices.
    NSString *answer = total >= 8 && highest / total >= 0.6 ? best : nil;
    [kept setObject:answer ?: @"" forKey:key];
    return answer;
}

NSString *SGLyricsTrackLanguage(NSString *trackID) {
    if (!trackID.length) return nil;
    return languageTag([NSUserDefaults.standardUserDefaults dictionaryForKey:SGKeyLyricsTrackLanguages][trackID]);
}

void SGLyricsSetTrackLanguage(NSString *trackID, NSString *tag) {
    if (!trackID.length || (tag && !languageTag(tag))) return;
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ SGLyricsSetTrackLanguage(trackID, tag); });
        return;
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableDictionary *stored = [[defaults dictionaryForKey:SGKeyLyricsTrackLanguages] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (tag) stored[trackID] = languageTag(tag);
    else [stored removeObjectForKey:trackID];
    for (NSString *other in [stored.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if (stored.count <= 500) break;
        if (![other isEqualToString:trackID]) [stored removeObjectForKey:other];
    }
    [defaults setObject:stored forKey:SGKeyLyricsTrackLanguages];
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsLanguageDidChangeNotification object:trackID];
}

NSString *SGLyricsSongLanguage(NSString *trackID, NSArray<SGKaraokeLine *> *lines) {
    return SGLyricsTrackLanguage(trackID) ?: SGLyricsDetectedLanguage(lines);
}

BOOL SGLyricsLanguageRule(NSString *language, BOOL *translation, BOOL *pronunciation) {
    NSString *key = baseLanguage(language);
    if (!key) return NO;
    id rule = [NSUserDefaults.standardUserDefaults dictionaryForKey:SGKeyLyricsLanguageRules][key];
    if (![rule isKindOfClass:NSDictionary.class] || ![rule[@"translation"] isKindOfClass:NSNumber.class] ||
        ![rule[@"pronunciation"] isKindOfClass:NSNumber.class]) return NO;
    if (translation) *translation = [rule[@"translation"] boolValue];
    if (pronunciation) *pronunciation = [rule[@"pronunciation"] boolValue];
    return YES;
}

void SGLyricsSetLanguageRule(NSString *language, BOOL translation, BOOL pronunciation) {
    NSString *key = baseLanguage(language);
    if (!key) return;
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ SGLyricsSetLanguageRule(key, translation, pronunciation); });
        return;
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableDictionary *rules = [[defaults dictionaryForKey:SGKeyLyricsLanguageRules] mutableCopy] ?: [NSMutableDictionary dictionary];
    rules[key] = @{@"translation": @(translation), @"pronunciation": @(pronunciation)};
    [defaults setObject:rules forKey:SGKeyLyricsLanguageRules];
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsLanguageDidChangeNotification object:nil];
}

NSString *SGLyricsSimplifiedTitle(NSString *title) {
    if (!title.length) return title;
    NSString *clean = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    BOOL changed = NO;
    NSString *opens = @"([【（", *closes = @")]】）";
    while (clean.length) {
        NSUInteger cut = NSNotFound;
        unichar last = [clean characterAtIndex:clean.length - 1];
        if ([closes rangeOfString:[NSString stringWithCharacters:&last length:1]].location != NSNotFound) {
            NSMutableArray<NSNumber *> *stack = [NSMutableArray array];
            // Walk balanced groups from the end so nested extras come off together. A group in
            // the middle stays: Love (Is All) Around is a title, not a trailing extra.
            for (NSUInteger i = clean.length; i > 0; i--) {
                unichar c = [clean characterAtIndex:i - 1];
                NSString *letter = [NSString stringWithCharacters:&c length:1];
                NSUInteger close = [closes rangeOfString:letter].location;
                NSUInteger open = [opens rangeOfString:letter].location;
                if (close != NSNotFound) [stack addObject:@(close)];
                else if (open != NSNotFound) {
                    if (!stack.count || stack.lastObject.unsignedIntegerValue != open) break;
                    [stack removeLastObject];
                    if (!stack.count) { cut = i - 1; break; }
                }
            }
        }
        if (cut == NSNotFound) {
            NSRange dash = [clean rangeOfString:@" - " options:NSBackwardsSearch];
            if (dash.location != NSNotFound) {
                NSString *suffix = [clean substringFromIndex:NSMaxRange(dash)];
                NSString *pattern = @"(?i)(?<![\\p{L}\\p{N}])(?:remaster(?:ed)?|live|version|edit|mix|mono|stereo|feat\\.|ft\\.|with|bonus|demo|acoustic|instrumental|from|single|radio|deluxe|anniversary|리마스터|라이브|ver\\.)(?![\\p{L}\\p{N}])";
                if ([suffix rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound) cut = dash.location;
            }
        }
        if (cut == NSNotFound) break;
        clean = [[clean substringToIndex:cut] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        changed = YES;
    }
    return changed && clean.length ? clean : title;
}
