#import <NaturalLanguage/NaturalLanguage.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/Lyrics/Lyrics.h"
#import "AIServicesInternal.h"

NSNotificationName const SGTranslatedTitleDidChangeNotification = @"spotifyglass.translatedTitleDidChange";

static BOOL contains(NSString *text, NSString *pattern) {
    return [text rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound;
}
BOOL SGLyricsTitleLatinArtist(NSString *artist) {
    if (![artist isKindOfClass:NSString.class] || artist.length > 64000 || !contains(artist, @"\\p{Latin}")) return NO;
    NSString *other = [artist stringByReplacingOccurrencesOfString:@"\\p{Latin}" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, artist.length)];
    return !contains(other, @"\\p{L}");
}
BOOL SGLyricsTitleNeedsTranslation(NSString *title, NSString *languageTag) {
    if (![title isKindOfClass:NSString.class] || !title.length || title.length > 64000 || !SGGoogleTargetLanguage(languageTag) || !contains(title, @"\\p{L}")) return NO;
    NSString *target = [[[languageTag stringByReplacingOccurrencesOfString:@"_" withString:@"-"] componentsSeparatedByString:@"-"] firstObject].lowercaseString;
    if ([target isEqual:@"iw"]) target = @"he";
    // Short titles give uncertain language guesses. A different writing system still supplies evidence;
    // shared Han characters alone do not distinguish Chinese from Japanese.
    NSDictionary *scripts = @{@"ko": @"Hangul", @"ja": @"Hiragana|Katakana|Han", @"zh": @"Han", @"yue": @"Han",
        @"ru": @"Cyrillic", @"uk": @"Cyrillic", @"bg": @"Cyrillic", @"el": @"Greek", @"ar": @"Arabic", @"fa": @"Arabic", @"he": @"Hebrew",
        @"th": @"Thai", @"hi": @"Devanagari"};
    NSString *script = scripts[target];
    if (!script && [@[@"en", @"fr", @"de", @"es", @"it", @"pt", @"nl", @"sv", @"da", @"no", @"nb", @"fi", @"pl", @"cs", @"vi", @"id", @"tr", @"ro"] containsObject:target]) script = @"Latin";
    if (script) {
        NSMutableArray *patterns = [NSMutableArray array];
        for (NSString *part in [script componentsSeparatedByString:@"|"]) [patterns addObject:[NSString stringWithFormat:@"\\p{%@}", part]];
        if (!contains(title, [patterns componentsJoinedByString:@"|"])) return YES;
    }
    NLLanguageRecognizer *recognizer = [NLLanguageRecognizer new];
    [recognizer processString:title];
    NSDictionary *hypotheses = [recognizer languageHypothesesWithMaximum:1];
    NSString *found = hypotheses.allKeys.firstObject;
    if (!found || [found isEqual:@"und"] || [hypotheses[found] doubleValue] < 0.8) return NO;
    NSString *source = [[found componentsSeparatedByString:@"-"] firstObject];
    if ([target isEqual:@"ja"] && [source isEqual:@"zh"] && !contains(title, @"\\p{Hiragana}|\\p{Katakana}")) return NO;
    return ![source isEqual:target];
}

static NSMutableSet *sg_asked;
static NSMutableDictionary *sg_titles;
static NSMutableArray *sg_order;

static NSArray<SGKaraokeLine *> *titleLines(NSString *title, NSString *artist) {
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *text in @[title, artist]) {
        SGKaraokeWord *word = [SGKaraokeWord new]; word.text = text;
        SGKaraokeLine *line = [SGKaraokeLine new]; line.words = @[word];
        [lines addObject:line];
    }
    return lines;
}
static void translateTitle(NSString *track, NSArray<SGKaraokeLine *> *lines, NSString *language, void (^done)(NSArray *, NSString *)) {
    // A distinct memo name keeps this pair away from a two-line song's lyrics.
    NSString *memo = [@"title:" stringByAppendingString:track];
    if (SGFlag(SGKeyLyricsBingTranslate, NO)) SGLyricsTranslateWithBing(memo, lines, language, done);
    else if (SGFlag(SGKeyLyricsGoogleTranslate, NO)) SGLyricsTranslateWithGoogle(memo, lines, language, done);
    else if (SGDeepLKeySet()) SGLyricsTranslateWithDeepL(memo, lines, language, done);
    else if (SGGeminiKeySet()) SGLyricsTranslateWithGemini(memo, lines, language, done);
    else if (SGClaudeKeySet()) SGLyricsTranslateWithClaude(memo, lines, language, done);
    else if (SGOpenAIKeySet()) SGLyricsTranslateWithOpenAI(memo, lines, language, done);
    else done(nil, nil);
}
NSString *SGLyricsTranslatedTitle(NSString *trackID, NSString *title, NSString *artist, NSString **artistOut) {
    if (artistOut) *artistOut = nil;
    if (!NSThread.isMainThread || !SGFlag(SGKeyLyricsTranslateTitles, NO) || ![trackID isKindOfClass:NSString.class] || !trackID.length || trackID.length > 1024 ||
        ![title isKindOfClass:NSString.class] || !title.length || title.length > 64000 || (artist && ![artist isKindOfClass:NSString.class]) || artist.length > 64000) return nil;
    artist = artist ?: @"";
    NSString *language = SGLyricsGeminiLanguage();
    NSDictionary *saved = sg_titles[trackID];
    if ([saved[@"language"] isEqual:language] && [saved[@"title"] isEqual:title] && [saved[@"artist"] isEqual:artist]) {
        if (artistOut) *artistOut = saved[@"translatedArtist"];
        return saved[@"translatedTitle"];
    }
    if ([sg_asked containsObject:trackID] || !SGLyricsTitleNeedsTranslation(title, language)) return nil;
    if (!sg_asked) { sg_asked = [NSMutableSet set]; sg_titles = [NSMutableDictionary dictionary]; sg_order = [NSMutableArray array]; }
    [sg_asked addObject:trackID];
    NSArray *lines = titleLines(title, artist);
    BOOL keepArtist = SGLyricsTitleLatinArtist(artist);
    __block BOOL finished = NO;
    void (^done)(NSArray *, NSString *) = ^(NSArray *answer, NSString *problem) {
        if (finished) return;
        finished = YES;
        // A switch or language change while the request was running must not put the old title on screen.
        if (!SGFlag(SGKeyLyricsTranslateTitles, NO) || ![SGLyricsGeminiLanguage() isEqual:language] || ![answer isKindOfClass:NSArray.class] || answer.count != 2 ||
            ![answer[0] isKindOfClass:NSString.class] || ![answer[1] isKindOfClass:NSString.class] || ![answer[0] length] || [answer[0] length] > 64000 || [answer[1] length] > 64000) return;
        if (sg_order.count >= 200) { [sg_titles removeObjectForKey:sg_order.firstObject]; [sg_order removeObjectAtIndex:0]; }
        sg_titles[trackID] = @{@"language": language, @"title": title, @"artist": artist, @"translatedTitle": answer[0],
            @"translatedArtist": keepArtist || ![answer[1] length] ? artist : answer[1]};
        [sg_order addObject:trackID];
        [NSNotificationCenter.defaultCenter postNotificationName:SGTranslatedTitleDidChangeNotification object:trackID];
    };
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!SGFlag(SGKeyLyricsTranslateTitles, NO) || ![SGLyricsGeminiLanguage() isEqual:language]) { done(nil, nil); return; }
        if (SGOnDeviceTranslation.translationAvailable) {
            [SGOnDeviceTranslation translate:@[title, artist] to:language done:^(NSArray *answer, NSString *problem) {
                if (answer.count == 2 && [answer[0] length]) done(answer, problem);
                else if (SGFlag(SGKeyLyricsTranslateTitles, NO)) translateTitle(trackID, lines, language, done);
                else done(nil, problem);
            }];
        } else translateTitle(trackID, lines, language, done);
    });
    return nil;
}
SGModRow *SGTranslateTitlesRow(void) {
    return SGOptionRow(SGL(@"settings.translation.titles.title", @"Translate song titles"),
        SGL(@"settings.translation.titles.subtitle", @"The title and artist go to the first translator that is on"), SGKeyLyricsTranslateTitles);
}
