#import <Foundation/Foundation.h>
#import "Shared/Lyrics/Lyrics.h"

static NSUInteger failures, checks;
static void expect(NSString *name, NSString *actual, NSString *expected) {
    checks++;
    if (actual == expected || [actual isEqualToString:expected]) return;
    failures++;
    fprintf(stderr, "FAIL %s: expected <%s>, got <%s>\n", name.UTF8String,
        expected ? expected.UTF8String : "nil", actual ? actual.UTF8String : "nil");
}

static void require(BOOL condition, NSString *name) {
    expect(name, condition ? @"yes" : @"no", @"yes");
}

static SGKaraokeLine *timedFixture(NSInteger shift) {
    NSArray *pieces = @[
        @[@"君", @100, @200, @NO], @[@"の", @200, @700, @YES],
        @[@"名", @800, @900, @YES], @[@"前", @900, @2500, @YES],
        @[@"Café", @3000, @3300, @NO]
    ];
    SGKaraokeLine *line = [SGKaraokeLine new];
    NSMutableArray *words = [NSMutableArray array];
    for (NSArray *piece in pieces) {
        SGKaraokeWord *word = [SGKaraokeWord new];
        word.text = piece[0]; word.start = [piece[1] integerValue] + shift;
        word.end = [piece[2] integerValue] + shift; word.joined = [piece[3] boolValue];
        [words addObject:word];
    }
    line.words = words; line.start = 100 + shift; line.end = 3300 + shift;
    return line;
}

static void preparedChecks(void) {
    SGKaraokeLine *line = timedFixture(0);
    SGLyricsPreparedExtras *latin = SGLyricsPrepareExtras(line, YES, NO, NO, YES, YES);
    expect(@"contextual timed Latin with accent preserved", SGKaraokeLineText(latin.pronunciation), @"kimi no namae Café");
    NSArray *expected = @[
        @[@"kimi", @0, @1, @100, @200], @[@"no", @1, @1, @200, @700],
        @[@"namae", @2, @2, @800, @2500], @[@"Café", @5, @4, @3000, @3300]
    ];
    require(latin.pronunciation.words.count == 4 && latin.sourceRanges.count == 4, @"four contextual source tokens");
    if (latin.pronunciation.words.count == 4 && latin.sourceRanges.count == 4) {
        for (NSUInteger i = 0; i < 4; i++) {
            SGKaraokeWord *word = latin.pronunciation.words[i];
            NSRange range = latin.sourceRanges[i].rangeValue;
            NSArray *want = expected[i];
            expect(@"token reading", word.text, want[0]);
            require(range.location == [want[1] unsignedIntegerValue] && range.length == [want[2] unsignedIntegerValue],
                    @"literal UTF-16 source range");
            require(word.start == [want[3] integerValue] && word.end == [want[4] integerValue],
                    @"unequal source durations, compound crosses source words");
        }
    }
    require(latin.ruby.count == 2, @"contextual kanji ruby prepared");
    if (latin.ruby.count == 2) {
        require(NSEqualRanges(latin.ruby[0].range, NSMakeRange(0, 1)) &&
                NSEqualRanges(latin.ruby[1].range, NSMakeRange(2, 2)), @"literal ruby source spans");
        expect(@"contextual compound ruby", latin.ruby[1].reading, @"なまえ");
    }
    SGLyricsPreparedExtras *hangul = SGLyricsPrepareExtras(line, YES, YES, YES, YES, YES);
    expect(@"timed Hangul alphabet", SGKaraokeLineText(hangul.pronunciation), @"키미노나마에 Café");
    expect(@"timed hiragana alphabet", SGKaraokeLineText(SGLyricsPrepareExtras(line, YES, NO, YES, YES, NO).pronunciation),
           @"きみのなまえ Café");
    SGKaraokeLine *duplicate = timedFixture(10000);
    SGLyricsPreparedExtras *chorus = SGLyricsPrepareExtras(duplicate, YES, NO, NO, YES, YES);
    require(chorus.pronunciation.words[2].start == 10800 && chorus.pronunciation.words[2].end == 12500,
            @"duplicate chorus keeps its own clocks");
    require(latin == SGLyricsPrepareExtras(timedFixture(0), YES, NO, NO, YES, YES),
            @"independent lyric views share the prepared result");
    SGKaraokeLine *coarse = [SGKaraokeLine new];
    SGKaraokeWord *phrase = [SGKaraokeWord new];
    phrase.text = @"君の名前"; phrase.start = 100; phrase.end = 2500;
    coarse.words = @[phrase]; coarse.start = 100; coarse.end = 2500;
    SGLyricsPreparedExtras *grouped = SGLyricsPrepareExtras(coarse, YES, NO, NO, YES, NO);
    require(grouped.pronunciation.words.count == 1 && grouped.pronunciation.words[0].start == 100 &&
            grouped.pronunciation.words[0].end == 2500 &&
            NSEqualRanges(grouped.sourceRanges[0].rangeValue, NSMakeRange(0, 4)),
            @"tokens within one provider word share its literal interval instead of invented clocks");
    expect(@"grouped contextual reading", SGKaraokeLineText(grouped.pronunciation), @"kimi no namae");
    line.timing = SGKaraokeTimingLine;
    require(SGLyricsPrepareExtras(line, YES, NO, NO, YES, NO).pronunciation.timing == SGKaraokeTimingLine,
            @"estimated input is not upgraded to word timing");
    line.timing = SGKaraokeTimingNone; line.start = line.end = 0;
    for (SGKaraokeWord *word in line.words) word.start = word.end = 0;
    SGLyricsPreparedExtras *plain = SGLyricsPrepareExtras(line, YES, NO, NO, YES, NO);
    require(plain.pronunciation.timing == SGKaraokeTimingNone && plain.pronunciation.words[2].end == 0,
            @"untimed input remains untimed");
    SGKaraokeLine *emoji = [SGKaraokeLine new];
    SGKaraokeWord *face = [SGKaraokeWord new], *kana = [SGKaraokeWord new];
    face.text = @"😀"; face.start = 10; face.end = 20;
    kana.text = @"きゃ"; kana.start = 20; kana.end = 900; kana.joined = YES;
    emoji.words = @[face, kana]; emoji.start = 10; emoji.end = 900;
    SGLyricsPreparedExtras *surrogate = SGLyricsPrepareExtras(emoji, YES, YES, NO, YES, NO);
    require(surrogate.sourceRanges.count == 2 && NSEqualRanges(surrogate.sourceRanges[1].rangeValue, NSMakeRange(2, 2)),
            @"supplementary-plane insert does not split source offsets");
    require(surrogate.pronunciation.words.lastObject.start == 20 && surrogate.pronunciation.words.lastObject.end == 900,
            @"kana digraph anchored after surrogate pair");
    SGKaraokeWord *name = [SGKaraokeWord new], *accent = [SGKaraokeWord new];
    kana.text = @"か\u3099";
    name.text = @"名前"; name.joined = YES; name.start = 900; name.end = 1200;
    accent.text = @"Cafe\u0301"; accent.start = 1400; accent.end = 1600;
    emoji.words = @[face, kana, name, accent]; emoji.end = 1600;
    SGLyricsPreparedExtras *decomposed = SGLyricsPrepareExtras(emoji, YES, NO, NO, YES, YES);
    expect(@"decomposed kana and Latin accents stay attached", SGKaraokeLineText(decomposed.pronunciation), @"😀 ga namae Cafe\u0301");
    NSArray *decomposedRanges = @[[NSValue valueWithRange:NSMakeRange(0, 2)], [NSValue valueWithRange:NSMakeRange(2, 2)],
        [NSValue valueWithRange:NSMakeRange(4, 2)], [NSValue valueWithRange:NSMakeRange(7, 5)]];
    require([decomposed.sourceRanges isEqual:decomposedRanges], @"composed token boundaries retain original UTF-16 offsets");
    require(decomposed.pronunciation.words.lastObject.start == 1400 && decomposed.pronunciation.words.lastObject.end == 1600,
            @"decomposed accent keeps its source word clock");
    SGKaraokeWord *prefix = [SGKaraokeWord new];
    prefix.text = [@"a" stringByPaddingToLength:3997 withString:@"a" startingAtIndex:0];
    prefix.start = 0; prefix.end = 10; face.joined = YES;
    emoji.words = @[prefix, face, kana, name, accent];
    SGLyricsPreparedExtras *bounded = SGLyricsPrepareExtras(emoji, YES, NO, NO, YES, YES);
    require(bounded.pronunciation.words.count == 5, @"a newline-free long line keeps every prepared reading word");
    if (bounded.pronunciation.words.count == 5) {
        expect(@"grapheme straddling the segment budget stays intact", bounded.pronunciation.words[2].text, @"ga");
        expect(@"long-line accent preserved", bounded.pronunciation.words[4].text, @"Cafe\u0301");
        require(NSEqualRanges(bounded.sourceRanges[2].rangeValue, NSMakeRange(3999, 2)) &&
                NSEqualRanges(bounded.sourceRanges[3].rangeValue, NSMakeRange(4001, 2)) &&
                NSEqualRanges(bounded.sourceRanges[4].rangeValue, NSMakeRange(4004, 5)),
                @"segmented readings map back to literal global UTF-16 offsets");
        require(bounded.pronunciation.words[3].start == 900 && bounded.pronunciation.words[3].end == 1200,
                @"segmented kanji reading retains the source interval");
    }
    require(bounded.ruby.count == 1 && NSEqualRanges(bounded.ruby[0].range, NSMakeRange(4001, 2)),
            @"long-line furigana survives with global source offsets");
    if (bounded.ruby.count) expect(@"long-line contextual ruby", bounded.ruby[0].reading, @"なまえ");
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
        NSString *latinPrefix = [@"a" stringByPaddingToLength:4000 withString:@"a" startingAtIndex:0];
        expect(@"long Latin reading uses bounded segments", SGLyricsRomanised([latinPrefix stringByAppendingString:@" 東京"], YES),
            [latinPrefix stringByAppendingString:@" toukyou"]);
        mode(YES, YES);
        expect(@"4001 kana remain visible through bounded segments", SGLyricsRomanised(overLimit, YES),
            [@"카" stringByPaddingToLength:4001 withString:@"카" startingAtIndex:0]);
        NSString *surrogateLimit = [[@"😀" stringByPaddingToLength:4000 withString:@"😀" startingAtIndex:0] stringByAppendingString:@"か"];
        mode(NO, NO);
        expect(@"Latin segment boundary preserves surrogate pairs", SGLyricsRomanised(surrogateLimit, YES),
            [[@"😀" stringByPaddingToLength:4000 withString:@"😀" startingAtIndex:0] stringByAppendingString:@"ka"]);
        mode(YES, NO);
        expect(@"Hangul segment boundary preserves surrogate pairs", SGLyricsRomanised(surrogateLimit, YES),
            [[@"😀" stringByPaddingToLength:4000 withString:@"😀" startingAtIndex:0] stringByAppendingString:@"카"]);
        dispatch_sync(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ preparedChecks(); });
        printf("%s: %lu pronunciation checks, %lu failures\n", failures ? "FAIL" : "PASS",
            (unsigned long)checks, (unsigned long)failures);
        return failures ? 1 : 0;
    }
}
