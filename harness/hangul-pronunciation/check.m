#import <Foundation/Foundation.h>
#import "Shared/Lyrics/Lyrics.h"

// The pronunciation API only needs this for song detection, not the line-reading tests below.
NSString *SGKaraokeLineText(SGKaraokeLine *line) { return nil; }

static NSUInteger failures, checks;
static void expect(NSString *name, NSString *actual, NSString *expected) {
    checks++;
    if (actual == expected || [actual isEqualToString:expected]) return;
    failures++;
    fprintf(stderr, "FAIL %s: expected <%s>, got <%s>\n", name.UTF8String,
        expected ? expected.UTF8String : "nil", actual ? actual.UTF8String : "nil");
}

int main(void) {
    @autoreleasepool {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        // Argument-domain defaults are process-local: never touch the user's saved preferences.
        void (^mode)(BOOL, BOOL) = ^(BOOL hangul, BOOL hiragana) {
            [defaults setVolatileDomain:@{SGKeyLyricsPronunciationHangul:@(hangul),
                SGKeyLyricsJapaneseKana:@(hiragana)} forName:NSArgumentDomain];
        };
        NSArray *latin = @[
            @[@"君の名前を呼んでいた", @NO, @"kimi no namae wo yon de i ta"],
            @[@"東京", @YES, @"toukyou"],
            @[@"我爱你，中国！", @NO, @"wǒ ài nǐ, zhōng guó!"],
            @[@"사랑해요 너를", @NO, @"salanghaeyo neoleul"],
            @[@"Привет, как дела?", @NO, @"Privet, kak dela?"],
            @[@"Καλημέρα κόσμε", @NO, @"Kalemera kosme"],
            @[@"สวัสดีครับ", @NO, @"swasdi khrab"],
            @[@"नमस्ते दुनिया", @NO, @"namaste duniya"],
            @[@"I love 東京 tonight", @YES, @"I love toukyou tonight"],
            @[@"Ich möchte Café", @NO, NSNull.null],
            @[@"Tôi yêu em", @NO, NSNull.null], @[@"♪", @NO, NSNull.null], @[@"", @NO, NSNull.null]
        ];
        // Existing literal fixtures from harness/lyrics; check again after Hangul to cover cache separation.
        for (NSUInteger pass = 0; pass < 2; pass++) {
            mode(NO, NO);
            for (NSArray *test in latin)
                expect(@"Latin compatibility", SGLyricsRomanised(test[0], [test[1] boolValue]),
                    test[2] == NSNull.null ? nil : test[2]);
            mode(NO, YES);
            expect(@"Hiragana compatibility", SGLyricsRomanised(@"君の名前を呼ぶ", YES), @"きみのなまえをよぶ");
            expect(@"Unchanged hiragana", SGLyricsRomanised(@"きみのなまえをよぶ、カナを！", YES), nil);
            mode(YES, YES);
            NSArray *japanese = @[
                @[@"あいうえお", @"아이우에오"],
                @[@"かきくけこ たちつてと ぱぴぷぺぽ", @"카키쿠케코 타치츠테토 파피푸페포"],
                @[@"がぎぐげご だぢづでど ばびぶべぼ", @"가기구게고 다지즈데도 바비부베보"],
                @[@"し じ ず ふ を は", @"시 지 즈 후 오 하"],
                @[@"きゃ しゅ ちょ ふぁ てぃ", @"캬 슈 초 파 티"],
                @[@"きって", @"킷테"], @[@"さんぽ", @"산포"], @[@"らー", @"라아"],
                @[@"ショー", @"쇼오"], @[@"キャ シュ チョ ファ ティ キッテ サンポ ラー", @"캬 슈 초 파 티 킷테 산포 라아"],
                @[@"東京", @"토우쿄우"], @[@"君の名前を呼ぶ", @"키미노나마에오요부"],
                @[@"I love 東京 tonight", @"I love 토우쿄우 tonight"],
                @[@"か\u3099", @"가"], @[@"😀きゃ！", @"😀캬!"],
                @[@"Cafe\u0301 きゃ", @"Cafe 캬"]
            ];
            for (NSArray *test in japanese)
                expect(@"Japanese Hangul (overrides hiragana)", SGLyricsRomanised(test[0], YES), test[1]);
            expect(@"Automatic Japanese detection", SGLyricsRomanised(@"きって", NO), @"킷테");
            NSArray *chinese = @[
                @[@"中 西 去 日 四 字 次 是 知 吃 二", @"중 시 취 르 쓰 쯔 츠 스 즈 츠 얼"],
                @[@"我爱你，中国！", @"워 아이 니,중 궈!"],
                @[@"女 绿 月 元 云", @"뉘 뤼 웨 위안 윈"],
                @[@"家 街 秋 熊", @"자 제 추 슝"],
                @[@"水 对 论", @"수이 두이 룬"],
                @[@"中国 xyz", @"중 궈 xyz"],
                @[@"嗯", @"ng"]
            ];
            for (NSArray *test in chinese)
                expect(@"Chinese Hangul", SGLyricsRomanised(test[0], NO), test[1]);
            expect(@"Korean unchanged", SGLyricsRomanised(@"사랑해요 너를", NO), @"salanghaeyo neoleul");
            expect(@"Other script unchanged", SGLyricsRomanised(@"Привет, как дела?", NO), @"Privet, kak dela?");
            expect(@"Latin text preserved beside Chinese", SGLyricsRomanised(@"中国 a shi café", NO), @"중 궈 a shi cafe");
        }
        NSString *atLimit = [@"か" stringByPaddingToLength:4000 withString:@"か" startingAtIndex:0];
        mode(YES, YES);
        expect(@"4000 UTF-16 units included", SGLyricsRomanised(atLimit, YES),
            [@"카" stringByPaddingToLength:4000 withString:@"카" startingAtIndex:0]);
        NSString *overLimit = [atLimit stringByAppendingString:@"か"];
        mode(NO, NO);
        NSString *latinOverLimit = SGLyricsRomanised(overLimit, YES);
        mode(YES, YES);
        expect(@"4001 falls back to Latin, not hiragana", SGLyricsRomanised(overLimit, YES), latinOverLimit);
        NSString *surrogateLimit = [[@"😀" stringByPaddingToLength:4000 withString:@"😀" startingAtIndex:0] stringByAppendingString:@"か"];
        mode(NO, NO);
        NSString *latinSurrogates = SGLyricsRomanised(surrogateLimit, YES);
        mode(YES, NO);
        expect(@"Cutoff counts UTF-16, not characters", SGLyricsRomanised(surrogateLimit, YES), latinSurrogates);
        printf("%s: %lu pronunciation checks, %lu failures\n", failures ? "FAIL" : "PASS",
            (unsigned long)checks, (unsigned long)failures);
        return failures ? 1 : 0;
    }
}
