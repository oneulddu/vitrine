// Checks the parts of lyrics translation that need no network: Musixmatch's community translations
// matched onto a song's lines as copies, and each translator's replies, language tags and batches.
// Replies below are made up, with no real lyrics. Exits non-zero on the first wrong answer.
#import <UIKit/UIKit.h>
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"

// What the files reach outside what is checked here; none of it is called.
@implementation SGLyricsResult
@end
void SGLyricsNoteReply(NSURLResponse *response, NSError *error) {}
NSString *SGLyricsTranslationLanguage(void) { return nil; }
SGModRow *SGStatActionRow(NSString *t, NSString *s, NSString *(^v)(void), void (^a)(void)) { return nil; }
SGModRow *SGOptionRow(NSString *t, NSString *s, NSString *k) { return nil; }
id SGKaraokeTrackFor(NSString *trackID) { return nil; }
BOOL SGFlag(NSString *key, BOOL fallback) { return fallback; }
UIViewController *SGTopController(void) { return nil; }

#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #cond); exit(1); } } while (0)

static NSArray<NSString *> *readReply(NSString *json, NSInteger status, NSUInteger count, NSString **problem) {
    *problem = nil;
    id root = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    return SGGeminiTranslationsIn(root, status, nil, count, problem);
}

static id json(NSString *text) {
    return [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingFragmentsAllowed error:nil];
}
static id chatReply(NSString *content) {
    return @{@"choices": @[@{@"message": @{@"content": content}}]};
}
static void checkProviders(void) {
    CHECK([SGDeepLTargetLanguage(@"zh-Hans-CN") isEqual:@"ZH-HANS"]);
    CHECK([SGDeepLTargetLanguage(@"zh-Hant") isEqual:@"ZH-HANT"]);
    CHECK([SGDeepLTargetLanguage(@"pt") isEqual:@"PT-BR"]);
    CHECK([SGDeepLTargetLanguage(@"pt-PT") isEqual:@"PT-PT"]);
    CHECK([SGDeepLTargetLanguage(@"en") isEqual:@"EN-US"]);
    CHECK([SGDeepLTargetLanguage(@"en-GB") isEqual:@"EN-GB"]);
    CHECK([SGDeepLTargetLanguage(@"nb-NO") isEqual:@"NB"]);
    CHECK([SGDeepLTargetLanguage(@"ko_KR") isEqual:@"KO"]);
    CHECK(!SGDeepLTargetLanguage(@"xx") && !SGDeepLTargetLanguage(@"en--US") && !SGDeepLTargetLanguage(nil));
    CHECK(!SGDeepLTargetLanguage((id)@42));
    CHECK(( [SGDeepLTranslationsIn(json(@"{\"translations\":[{\"text\":\"sample A\"},{\"text\":\"sample B\"}]}"), 2) isEqual:@[@"sample A", @"sample B"]] ));
    for (NSString *bad in @[@"null", @"[]", @"{}", @"{\"translations\":null}", @"{\"translations\":[null]}", @"{\"translations\":[{\"text\":7}]}", @"{\"translations\":[{\"text\":null}]}" ]) {
        CHECK(!SGDeepLTranslationsIn(json(bad), 1));
    }
    CHECK(!SGDeepLTranslationsIn(json(@"{\"translations\":[{\"text\":\"sample\"}]}"), 2));

    // The 51st nonblank line starts a new DeepL request without shifting any original indices.
    NSMutableArray *many = [NSMutableArray arrayWithObject:@""];
    for (NSUInteger i = 0; i < 51; i++) [many addObject:[NSString stringWithFormat:@"sample %lu", (unsigned long)i]];
    NSArray *batches = SGLyricsTranslationBatches(many, 50, 16000);
    CHECK(batches.count == 2 && [batches[0] count] == 50 && [batches[1] count] == 1);
    CHECK(( [batches[0][0] isEqual:@1] && [batches[1][0] isEqual:@51] ));
    CHECK(( [SGLyricsTranslationBatches(@[@"A", @" ", @"B", @"C"], 50, 3) isEqual:@[@[@0, @2], @[@3]]] ));
    CHECK(( [SGLyricsTranslationBatches(@[@"", @" ", @"\n"], 50, 3500) count] == 0 ));
    CHECK(!SGLyricsTranslationBatches(@[@"A"], 0, 3500));
    CHECK(!SGLyricsTranslationBatches(@[@"A"], 50, 0));
    CHECK(!SGLyricsTranslationBatches((id)@[@42], 50, 3500));
    NSString *full = [@"A" stringByPaddingToLength:3500 withString:@"A" startingAtIndex:0];
    CHECK(( [SGLyricsTranslationBatches(@[full, @"B"], 2000, 3500) isEqual:@[@[@0], @[@1]]] ));
    CHECK(!SGLyricsTranslationBatches(@[[full stringByAppendingString:@"A"]], 2000, 3500));
    CHECK(( [SGLyricsTranslationBatches(@[@"😀", @"界"], 2000, 4) isEqual:@[@[@0, @1]]] ));
    NSMutableArray *tooMany = [NSMutableArray array];
    for (NSUInteger i = 0; i < 2001; i++) [tooMany addObject:@""];
    CHECK(!SGLyricsTranslationBatches(tooMany, 50, 3500));
    NSMutableArray *tooLong = [NSMutableArray array];
    for (NSUInteger i = 0; i < 40; i++) [tooLong addObject:full];
    CHECK(!SGLyricsTranslationBatches(tooLong, 50, 3500));

    CHECK([SGGoogleTargetLanguage(@"zh-Hans") isEqual:@"zh-CN"]);
    CHECK([SGGoogleTargetLanguage(@"zh-Hant-TW") isEqual:@"zh-TW"]);
    CHECK([SGGoogleTargetLanguage(@"he-IL") isEqual:@"iw"]);
    CHECK([SGGoogleTargetLanguage(@"nb") isEqual:@"no"]);
    CHECK([SGGoogleTargetLanguage(@"pt-BR") isEqual:@"pt-BR"]);
    CHECK(!SGGoogleTargetLanguage(@"en&tl=xx") && !SGGoogleTargetLanguage(@"en--US"));
    CHECK(SGGoogleKeepsLine(@"♪") && SGGoogleKeepsLine(@" ♪ ♪ ") && SGGoogleKeepsLine(@" [Chorus] "));
    CHECK(!SGGoogleKeepsLine(@"♪ sample") && !SGGoogleKeepsLine(@"[sample] words") && !SGGoogleKeepsLine(@"[A] [B]"));
    CHECK(!SGGoogleKeepsLine(@"[]") && !SGGoogleKeepsLine(@" "));
    id google = json(@"[[[\"sample A\\n\",\"source\",null],[\"sample B\",\"source\"]],null,\"en\"]");
    CHECK(( [SGGoogleTranslationLinesIn(google, 2) isEqual:@[@"sample A", @"sample B"]] ));
    CHECK(!SGGoogleTranslationLinesIn(google, 3));
    CHECK(( [SGGoogleTranslationLinesIn(@[@[@[@"A\r\nB"]]], 2) isEqual:@[@"A", @"B"]] ));
    CHECK(!SGGoogleTranslationLinesIn(@[@[@[@"A\nB\n"]]], 2));
    CHECK([SGGoogleTranslationTextIn(@[@[@[@"A\nB"]]]) isEqual:@"A\nB"]); // a single source line can contain newlines
    for (NSString *bad in @[@"null", @"{}", @"[]", @"[null]", @"[[]]", @"[[null]]", @"[[[]]]", @"[[[null]]]", @"[[[42]]]", @"[[[\"A\"],null]]"]) {
        CHECK(!SGGoogleTranslationTextIn(json(bad)));
    }
    NSString *oversized = [@"A" stringByPaddingToLength:128001 withString:@"A" startingAtIndex:0];
    CHECK(!SGGoogleTranslationTextIn(@[@[@[oversized]]]));
    CHECK(!SGDeepLTranslationsIn(@{@"translations": @[@{@"text": oversized}]}, 1));
    NSString *form = [[NSString alloc] initWithData:SGGoogleTranslationForm(@"A &+=%\n한😀", @"he") encoding:NSUTF8StringEncoding];
    CHECK([form isEqual:@"client=gtx&sl=auto&tl=iw&dt=t&q=A%20%26%2B%3D%25%0A%ED%95%9C%F0%9F%98%80"]);
    CHECK(!SGGoogleTranslationForm([full stringByAppendingString:@"A"], @"en"));

    CHECK([SGOpenAICompletionURL(@"https://api.openai.com/v1/").absoluteString isEqual:@"https://api.openai.com/v1/chat/completions"]);
    CHECK(SGOpenAICompletionURL(@"https://openrouter.ai/api/v1"));
    CHECK(SGOpenAICompletionURL(@"http://localhost:8080/v1"));
    CHECK(SGOpenAICompletionURL(@"http://127.0.0.1:8080"));
    CHECK(SGOpenAICompletionURL(@"http://server.local/v1"));
    for (NSString *bad in @[@"", @"http://example.com/v1", @"http://localhost.evil/v1", @"http://server.local.evil/v1", @"ftp://localhost/v1", @"https://user:secret@example.com/v1", @"https://example.com/v1?q=x", @"https://example.com/v1#x", @"https://example.com:65536/v1", @"https://exa mple.com", @"/v1"]) {
        CHECK(!SGOpenAICompletionURL(bad));
    }
    CHECK(( [SGOpenAITranslationsIn(chatReply(@"[\"A\",\"\"]"), 2) isEqual:@[@"A", @""]] ));
    CHECK(( [SGOpenAITranslationsIn(chatReply(@"```json\n[\"A\",\"B\"]\n```"), 2) isEqual:@[@"A", @"B"]] ));
    CHECK(( [SGOpenAITranslationsIn(chatReply(@" ```JSON\r\n{\"lines\":[\"A\",\"B\"]}\r\n``` "), 2) isEqual:@[@"A", @"B"]] ));
    CHECK(( [SGOpenAITranslationsIn(chatReply(@"```\n[\"A\"]\n```"), 1) isEqual:@[@"A"]] ));
    for (NSString *bad in @[@"null", @"[7]", @"[null]", @"[{}]", @"[\"A\",\"B\"]", @"{\"a\":[\"A\"],\"b\":[\"B\"]}", @"```json", @"```json\n[\"A\"]", @"```xml\n[\"A\"]\n```", @"Here: [\"A\"]"]) {
        CHECK(!SGOpenAITranslationsIn(chatReply(bad), 1));
    }
    for (NSString *bad in @[@"null", @"{}", @"{\"choices\":null}", @"{\"choices\":[null]}", @"{\"choices\":[{\"message\":null}]}", @"{\"choices\":[{\"message\":{\"content\":[]}}]}"]) {
        CHECK(!SGOpenAITranslationsIn(json(bad), 1));
    }
    CHECK(!SGOpenAITranslationsIn(chatReply([@"A" stringByPaddingToLength:256001 withString:@"A" startingAtIndex:0]), 1));
    puts("DeepL / Google / OpenAI: mapping, malformed replies, line counts, bounds, form encoding and URL checks passed");
}

int main(void) {
    @autoreleasepool {
        // Musixmatch's translations go on copies of the lines they match, by the folded text.
        NSArray<SGKaraokeLine *> *lines = SGKaraokeEstimatedLines(@[@0, @2000, @4000, @6000],
                                                                  @[@"Où est l'amour ?", @"Yeah", @"Rien", @""]);
        CHECK(lines.count >= 3);
        lines[2].translation = @"Nothing";
        NSDictionary *byLine = @{SGMusixmatchLineKey(@"ou est L'AMOUR"): @"Where is love?", SGMusixmatchLineKey(@"rien"): @"None"};
        NSArray<SGKaraokeLine *> *translated = SGMusixmatchTranslatedLines(lines, byLine);
        CHECK(translated && translated != lines && translated.count == lines.count);
        CHECK([translated[0].translation isEqualToString:@"Where is love?"] && translated[0] != lines[0]);
        CHECK(!lines[0].translation);                                  // the lines kept before are left as they were
        CHECK(translated[0].start == lines[0].start && translated[0].end == lines[0].end
              && translated[0].words == lines[0].words && translated[0].timing == lines[0].timing);
        CHECK(translated[1] == lines[1] && !translated[1].translation);  // no match: the same line
        CHECK([translated[2].translation isEqualToString:@"Nothing"]);   // a translation of its own stays
        CHECK(!SGMusixmatchTranslatedLines(lines, @{@"nothing here": @"x"}));

        // Gemini's language by the whole tag, so the script survives.
        NSLocale *english = [NSLocale localeWithLocaleIdentifier:@"en"];
        CHECK(![[english localizedStringForLocaleIdentifier:@"zh-Hant"] isEqualToString:[english localizedStringForLocaleIdentifier:@"zh-Hans"]]);

        // Gemini's reply: lines, or why there are none.
        NSString *problem;
        NSArray<NSString *> *got = readReply(@"{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"[\\\"a\\\",\\\"\\\"]\"}]},\"finishReason\":\"STOP\"}]}", 200, 2, &problem);
        CHECK([got isEqualToArray:(@[@"a", @""])] && !problem);
        CHECK(!readReply(@"{\"promptFeedback\":{\"blockReason\":\"PROHIBITED_CONTENT\"}}", 200, 2, &problem) && [problem containsString:@"filters"]);
        CHECK(!readReply(@"{\"candidates\":[{\"finishReason\":\"RECITATION\"}]}", 200, 2, &problem) && [problem containsString:@"repeated"]);
        CHECK(!readReply(@"{\"candidates\":[{\"finishReason\":\"SAFETY\"}]}", 200, 2, &problem) && [problem containsString:@"filters"]);
        CHECK(!readReply(@"{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"[\\\"a\\\"]\"}]},\"finishReason\":\"STOP\"}]}", 200, 2, &problem)
              && [problem containsString:@"1 lines for the song's 2"]);
        CHECK(!readReply(@"{\"error\":{}}", 403, 2, &problem) && [problem containsString:@"key"]);
        CHECK(!readReply(@"{\"error\":{\"message\":\"API key not valid. Please pass a valid API key.\"}}", 400, 2, &problem) && [problem containsString:@"key"]);
        CHECK(!readReply(@"{\"error\":{\"message\":\"Invalid JSON payload\"}}", 400, 2, &problem) && [problem containsString:@"Invalid JSON payload"]);
        CHECK(!readReply(@"{\"error\":{}}", 503, 2, &problem) && [problem containsString:@"busy"]);
        CHECK(!readReply(@"{\"error\":{\"status\":\"UNAUTHENTICATED\"}}", 401, 2, &problem) && [problem containsString:@"key"]);
        CHECK(!readReply(@"{\"error\":{}}", 429, 2, &problem) && [problem containsString:@"limit"]);
        CHECK(!readReply(@"{}", 200, 2, &problem) && [problem containsString:@"could not be read"]);
        checkProviders();
        puts("lyrics translation: all checks passed");
    }
    return 0;
}
