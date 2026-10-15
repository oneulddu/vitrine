// Checks what is new in the lyrics sources and their words without the phone or the network: lines in
// Thai and the scripts like it split at the dictionary's words (KaraokeTiming.m), KuGou's KRC unpacked
// and read (KuGou.m, through NetEase.m's parser), and the QQ Music and KuGou asks matching a track
// against made-up search replies, plus Bugs, Genie, LyricsPlus and Deezer parser and request checks.
// The requests are answered here, by host. Any file named on the
// command line is a real KuGou download or QQ lyrics reply, saved as JSON, and only its line count is
// printed. Exits non-zero on the first wrong answer.
#import <UIKit/UIKit.h>
#import <zlib.h>
#import "Shared/LyricsSources/LyricsSources.h"

#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #cond); exit(1); } } while (0)

// What the sources reach outside themselves for: the requests, answered by sg_answer.
@implementation SGLyricsResult
@end
@implementation SGLyricsQuery
@end
void SGLyricsPageLines(NSArray<SGKaraokeLine *> *lines, NSArray<NSNumber *> **starts, NSArray<NSString *> **texts) {
    NSMutableArray *at = [NSMutableArray array], *said = [NSMutableArray array];
    for (SGKaraokeLine *line in lines) {
        [at addObject:@(line.start)];
        [said addObject:SGKaraokeLineText(line)];
    }
    *starts = at;
    *texts = said;
}
void SGLyricsNoteReply(NSURLResponse *response, NSError *error) {}
NSURL *SGLyricsURL(NSString *base, NSDictionary<NSString *, NSString *> *query) {
    NSURLComponents *url = [NSURLComponents componentsWithString:base];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    [query enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [items addObject:[NSURLQueryItem queryItemWithName:name value:value]];
    }];
    url.queryItems = items;
    return url.URL;
}
static id (^sg_answer)(NSURL *url, id body);
void SGLyricsGetJSON(NSURL *url, NSDictionary *headers, void (^done)(id root)) {
    CHECK(![url.host isEqualToString:@"lrclib.net"]); // LRCLIB must use the bounded transport.
    done(sg_answer(url, nil));
}
void SGLyricsPostJSON(NSURL *url, NSDictionary *headers, id body, void (^done)(id root)) { done(sg_answer(url, body)); }

// The settings row is linked but never opened. Credentials and network answers are made up here.
NSString *SGL(NSString *key, NSString *english) { return english; }
SGModRow *SGStatActionRow(NSString *title, NSString *subtitle, NSString *(^value)(void), void (^action)(void)) { return nil; }
UIViewController *SGTopController(void) { return nil; }
NSArray *SGLyricsOrder(void) { return @[]; }
void SGLyricsSetOrder(NSArray *keys) {}
void SGDeezerAskWith(NSString *arl, SGLyricsQuery *query, void (^done)(SGLyricsResult *));
static id (^sg_sourceAnswer)(NSURL *, NSDictionary *, NSData *, NSInteger *);
static NSUInteger sg_sourceRequests;
void SGLyricsSourceRequest(NSURL *url, NSDictionary *headers, NSData *body, void (^done)(NSData *, NSInteger)) {
    CHECK(NSThread.isMainThread);
    sg_sourceRequests++;
    NSInteger status = 200;
    id answer;
    if ([url.host isEqualToString:@"lrclib.net"]) {
        CHECK([headers[@"User-Agent"] hasPrefix:@"Vitrine "] && !body);
        answer = sg_answer(url, nil);
    } else answer = sg_sourceAnswer(url, headers, body, &status);
    NSData *data = [answer isKindOfClass:NSString.class] ? [answer dataUsingEncoding:NSUTF8StringEncoding] :
        answer ? [NSJSONSerialization dataWithJSONObject:answer options:NSJSONWritingFragmentsAllowed error:nil] : nil;
    done(data, status);
}

static void checkReadingAndSearch(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id prior = [defaults objectForKey:SGKeyLyricsJapaneseKana];
    [defaults setBool:NO forKey:SGKeyLyricsJapaneseKana];
    NSString *romaji = SGLyricsRomanised(@"君の名前を呼ぶ", YES);
    [defaults setBool:YES forKey:SGKeyLyricsJapaneseKana];
    NSString *hiragana = SGLyricsRomanised(@"君の名前を呼ぶ", YES);
    printf("Japanese reading: %s -> %s\n", romaji.UTF8String, hiragana.UTF8String);
    CHECK([hiragana isEqualToString:@"きみのなまえをよぶ"]);
    CHECK(!SGLyricsRomanised(@"きみのなまえをよぶ、カナを！", YES));
    CHECK([SGLyricsRomanised(@"東京 Café を 名前!", YES) isEqualToString:@"とうきょう Café を なまえ!"]);
    [defaults setBool:NO forKey:SGKeyLyricsJapaneseKana];
    CHECK([SGLyricsRomanised(@"君の名前を呼ぶ", YES) isEqualToString:romaji]);
    if (prior) [defaults setObject:prior forKey:SGKeyLyricsJapaneseKana];
    else [defaults removeObjectForKey:SGKeyLyricsJapaneseKana];

    NSDictionary *plain = @{@"id": @1, @"duration": @200, @"plainLyrics": @"a line"};
    NSDictionary *near = @{@"id": @2, @"trackName": @"Song", @"artistName": @"Singer", @"albumName": NSNull.null,
                           @"duration": @200.2, @"syncedLyrics": @"[00:01.00]a line", @"instrumental": NSNull.null};
    NSDictionary *far = @{@"id": @3, @"duration": @180, @"syncedLyrics": @"[00:02.00]another line"};
    __block id reply = @[plain, far, near, NSNull.null, @{@"id": @YES}, @{@"id": @"4"}];
    sg_answer = ^id(NSURL *url, id body) {
        CHECK([url.host isEqualToString:@"lrclib.net"] && [url.path isEqualToString:@"/api/search"]);
        return reply;
    };
    __block NSArray<NSDictionary *> *found;
    SGLrcLibSearch(@"Song", @"Singer", 200, ^(NSArray *records) { CHECK(NSThread.isMainThread); found = records; });
    CHECK(found.count == 3 && [found[0][@"id"] isEqual:@2] && [found[1][@"id"] isEqual:@3] && [found[2][@"id"] isEqual:@1]);
    CHECK([found[0][@"title"] isEqual:@"Song"] && [found[0][@"artist"] isEqual:@"Singer"] && [found[0][@"album"] isEqual:@""]);
    CHECK([found[0][@"synced"] boolValue] && ![found[0][@"instrumental"] boolValue] && [found[0][@"seconds"] isEqual:@200.2]);
    CHECK([found[0][@"record"] isEqual:near]);
    CHECK([SGLrcLibRecordResult(near).provider isEqual:@"LRCLIB"] && SGLrcLibRecordResult(plain).karaokeLines.count == 1);
    CHECK(!SGLrcLibRecordResult(@{@"plainLyrics": @"  ", @"instrumental": NSNull.null}));
    CHECK(SGLrcLibRecordResult(@{@"instrumental": @YES}).instrumental);
    SGLrcLibSearch(@"Song", @"Singer", 0, ^(NSArray *records) { found = records; });
    CHECK([found[0][@"id"] isEqual:@3] && [found[1][@"id"] isEqual:@2]);
    NSMutableArray *many = [NSMutableArray array];
    for (NSUInteger i = 1; i <= 25; i++) [many addObject:@{@"id": @(i), @"duration": @(i), @"syncedLyrics": @"[00:01]line"}];
    reply = many;
    SGLrcLibSearch(@"Song", @"", 25, ^(NSArray *records) { found = records; });
    CHECK(found.count == 20 && [found[0][@"id"] isEqual:@25] && [found.lastObject[@"id"] isEqual:@6]);
    // Only the first 100 wire records count, even when they are malformed.
    NSMutableArray *over100 = [NSMutableArray array];
    for (NSUInteger i = 0; i < 100; i++) [over100 addObject:NSNull.null];
    [over100 addObject:near]; reply = over100;
    SGLrcLibSearch(@"Song", @"Singer", 200, ^(NSArray *records) { found = records; });
    CHECK(!found.count);
    NSString *tooManyBytes = [@"é" stringByPaddingToLength:131073 withString:@"é" startingAtIndex:0];
    NSString *atByteLimit = [@"a" stringByPaddingToLength:256 * 1024 withString:@"a" startingAtIndex:0];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < 4000; i++) [rows addObject:@"[00:01]line"];
    NSString *atLineLimit = [rows componentsJoinedByString:@"\r\n"];
    NSString *tooManyLines = [atLineLimit stringByAppendingString:@"\r\n[00:02]extra"];
    CHECK(SGLrcLibRecordResult(@{@"plainLyrics": atByteLimit, @"instrumental": @YES}).instrumental);
    CHECK(SGLrcLibRecordResult(@{@"syncedLyrics": atLineLimit}).karaokeLines.count == 4000);
    for (NSString *field in @[@"plainLyrics", @"syncedLyrics"]) {
        for (NSString *oversize in @[tooManyBytes, [atByteLimit stringByAppendingString:@"a"], tooManyLines]) {
            NSDictionary *bad = @{@"id": @99, field: oversize, @"instrumental": @YES};
            CHECK(!SGLrcLibRecordResult(bad));
            reply = @[bad, near];
            SGLrcLibSearch(@"Song", @"Singer", 200, ^(NSArray *records) { found = records; });
            CHECK(found.count == 1 && [found[0][@"id"] isEqual:@2]);
            sg_answer = ^id(NSURL *url, id body) { CHECK([url.path isEqualToString:@"/api/get/99"]); return bad; };
            __block SGLyricsResult *oversizedPin;
            SGLrcLibGetID(@99, ^(SGLyricsResult *result) { oversizedPin = result; });
            CHECK(!oversizedPin);
            sg_answer = ^id(NSURL *url, id body) { return reply; };
        }
    }
    reply = nil;
    SGLrcLibSearch(@"Song", @"Singer", 200, ^(NSArray *records) { found = records; });
    CHECK(found && !found.count);
    SGLrcLibSearch(@"", @"", 200, ^(NSArray *records) { found = records; });
    CHECK(found && !found.count);
    __block BOOL returnedOnMain = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        SGLrcLibSearch(@"Song", @"Singer", 200, ^(NSArray *records) {
            CHECK(NSThread.isMainThread && records && !records.count);
            returnedOnMain = YES;
        });
    });
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!returnedOnMain && limit.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    CHECK(returnedOnMain);
    sg_answer = ^id(NSURL *url, id body) { CHECK([url.path isEqualToString:@"/api/get/2"]); return near; };
    __block SGLyricsResult *got;
    SGLrcLibGetID(@2, ^(SGLyricsResult *result) { got = result; });
    CHECK(got.karaokeLines.count == 1 && [got.provider isEqualToString:@"LRCLIB"]);
    printf("LRCLIB: bounded transport, 100-record input/20-result output, 256 KiB/4000-line caps, ranking and pinned lookup passed\n");
}

static NSString *param(NSURL *url, NSString *name) {
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) {
        if ([item.name isEqualToString:name]) return item.value;
    }
    return nil;
}

static NSArray<SGKaraokeWord *> *piecesOf(NSString *text) {
    return SGKaraokeStaticLines(@[text]).firstObject.words;
}

// The words of an unspaced token come back flush, so the line reads as it was written.
static void checkSplit(NSString *text, BOOL split) {
    NSArray<SGKaraokeWord *> *words = piecesOf(text);
    printf("%lu pieces: %s\n", (unsigned long)words.count, [[words valueForKey:@"text"] componentsJoinedByString:@"|"].UTF8String);
    CHECK([SGKaraokeLineText(SGKaraokeStaticLines(@[text]).firstObject) isEqualToString:text]);
    CHECK(!split || words.count > 1);
}

// KRC as KuGou packs it: "krc1", then the zlib of the text XORed with the key, all in base64.
static NSString *packed(NSString *krc, NSString *magic) {
    NSData *text = [krc dataUsingEncoding:NSUTF8StringEncoding];
    uLongf length = compressBound(text.length);
    NSMutableData *zipped = [NSMutableData dataWithLength:length];
    compress(zipped.mutableBytes, &length, text.bytes, text.length);
    zipped.length = length;
    static const uint8_t key[16] = {64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105};
    uint8_t *bytes = zipped.mutableBytes;
    for (NSUInteger i = 0; i < zipped.length; i++) bytes[i] ^= key[i % 16];
    NSMutableData *all = [[magic dataUsingEncoding:NSASCIIStringEncoding] mutableCopy];
    [all appendData:zipped];
    return [all base64EncodedStringWithOptions:0];
}

static NSString *const kKRC = @"﻿[id:$00000000]\r\n[ar:Someone]\r\n"
    "[1000,2000]<0,500,0>Hel<500,300,0>lo <800,700,0>world\r\n"
    "[4000,1500]<0,400,0>你<400,400,0>好<800,0,0>啊\r\n"
    "[7000,100]<0,300,0>late\r\n";

static void checkLive(NSString *path) {
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:nil];
    if (root[@"content"]) {
        NSArray<SGKaraokeLine *> *lines = SGKuGouLines(root[@"content"]);
        printf("%s: KRC, %lu word timed lines; first \"%s\" at %ld\n", path.lastPathComponent.UTF8String, (unsigned long)lines.count,
               SGKaraokeLineText(lines.firstObject).UTF8String, (long)lines.firstObject.start);
        CHECK(lines.count);
        return;
    }
    id lyric = root[@"music.musichallSong.PlayLyricInfo.GetPlayLyricInfo"][@"data"][@"lyric"];
    NSString *lrc = [[NSString alloc] initWithData:[[NSData alloc] initWithBase64EncodedString:lyric options:0] encoding:NSUTF8StringEncoding];
    SGLyricsResult *result = SGLyricsLRCResult(lrc);
    printf("%s: QQ LRC, %lu timed lines\n", path.lastPathComponent.UTF8String, (unsigned long)result.karaokeLines.count);
    CHECK(result.synced && result.karaokeLines.count);
}

static id deezerBody(NSDictionary *lyrics) { return @{@"data": @{@"track": @{@"lyrics": lyrics}}}; }

static void checkNewSources(void) {
    SGLyricsResult *result = SGBugsResult(@{@"lyrics": @"0.3005|Made up＃8.9|Another line＃"}, YES);
    CHECK(result.synced && result.karaokeLines.firstObject.start == 301 && result.karaokeLines[1].start == 8900);
    CHECK([result.provider isEqualToString:@"Bugs"]);
    CHECK(!SGBugsResult(@{@"lyrics": @"20|Later＃1|Earlier"}, YES));
    CHECK(!SGBugsResult(@{@"lyrics": @"bad＃nope＃1|Only one"}, YES));
    CHECK(!SGBugsResult(@{@"lyrics": @"nan|Bad＃inf|Bad＃-2|Bad"}, YES));
    CHECK(SGBugsResult(@{@"lyrics": @"bad＃1|Half"}, YES).synced);
    result = SGBugsResult(@{@"lyrics": @"Made up\r\nAnother line"}, NO);
    CHECK(!result.synced && result.texts.count == 2 && [result.starts isEqual:(@[@0, @0])]);

    result = SGGenieResult(@"null({\"8700\":\"Later\",\"0\":\"First\"});");
    CHECK(result.synced && result.karaokeLines[1].start == 8700 && [result.provider isEqualToString:@"Genie"]);
    CHECK(!SGGenieResult(@"null({\"oops\":\"No\"})"));
    CHECK(!SGGenieResult(@"null({\"0\":null})") && !SGGenieResult(@"null({\"1.2\":\"No\"})"));
    CHECK(!SGGenieResult(@"null({\"99999999999999999999\":\"No\"})"));
    CHECK(!SGGenieResult(@"null([1,2])") && !SGGenieResult(@"broken"));

    NSDictionary *plus = @{@"type": @"Syllable", @"metadata": @{@"source": @"Made-up catalog"}, @"lyrics": @[
        @{@"time": @1000, @"duration": @2000, @"text": @"Hello world", @"element": @{@"singer": @"v1"}, @"syllabus": @[
            @{@"time": @1000, @"duration": @200, @"text": @"Hel"},
            @{@"time": @1200, @"duration": @300, @"text": @"lo "},
            @{@"time": @1500, @"duration": @500, @"text": @"world"},
            @{@"time": @1700, @"duration": @200, @"text": @"oh", @"isBackground": @YES},
        ]} ]};
    result = SGLyricsPlusResult(plus);
    CHECK(result.wordTimed && result.karaokeLines.firstObject.timing == SGKaraokeTimingWords);
    CHECK([SGKaraokeLineText(result.karaokeLines.firstObject) isEqualToString:@"Hello world"]);
    CHECK(result.karaokeLines.firstObject.words[1].joined && !result.karaokeLines.firstObject.words[2].joined);
    CHECK(result.karaokeLines.firstObject.backing.start == 1700 && [result.provider isEqualToString:@"LyricsPlus · Made-up catalog"]);
    NSMutableDictionary *wordPlus = [plus mutableCopy];
    wordPlus[@"type"] = @"Word";
    CHECK(SGLyricsPlusResult(wordPlus).wordTimed);
    NSDictionary *linePlus = @{@"type": @"Line", @"metadata": @{@"source": @42}, @"lyrics": @[
        @{@"time": @5000, @"duration": @1000, @"text": @"Second"}, @{@"time": @1000, @"duration": @1000, @"text": @"First"}]};
    result = SGLyricsPlusResult(linePlus);
    CHECK(result.synced && !result.wordTimed && result.karaokeLines.firstObject.start == 1000 && [result.provider isEqualToString:@"LyricsPlus"]);
    CHECK(!SGLyricsPlusResult(@{@"type": @"Word", @"lyrics": @[@{@"time": @0, @"duration": @1, @"text": @"x", @"syllabus": @[@{@"text": @"x", @"time": @"nan", @"duration": @1}]}]}));
    CHECK(!SGLyricsPlusResult(@{@"type": @"Line", @"lyrics": @[@{@"time": @YES, @"duration": @1, @"text": @"x"}]}));

    NSDictionary *deezer = deezerBody(@{@"text": @"Fallback", @"synchronizedLines": @[@{@"milliseconds": @9999, @"line": @"Fallback line"}], @"synchronizedWordByWordLines": @[
        @{@"start": @1000, @"end": @2400, @"words": @[@{@"start": @1000, @"end": @1500, @"word": @"Made"}, @{@"start": @1600, @"end": @2300, @"word": @"up"}]}]});
    result = SGDeezerResult(deezer);
    CHECK(result.wordTimed && result.karaokeLines.firstObject.words[1].start == 1600 && [result.provider isEqualToString:@"Deezer"]);
    CHECK([SGKaraokeLineText(result.karaokeLines.firstObject) isEqualToString:@"Made up"]);
    result = SGDeezerResult(deezerBody(@{@"synchronizedWordByWordLines": @[@{@"start": @1, @"end": @0}], @"synchronizedLines": @[@{@"milliseconds": @8700, @"line": @"Later"}, @{@"milliseconds": @0, @"line": @"First"}]}));
    CHECK(result.synced && !result.wordTimed && result.karaokeLines[1].start == 8700);
    result = SGDeezerResult(deezerBody(@{@"text": @"Plain\r\nMade up", @"synchronizedLines": NSNull.null}));
    CHECK(!result.synced && result.texts.count == 2);
    for (id odd in @[NSNull.null, @42, @YES, @"error", @[], @{}]) {
        CHECK(!SGBugsResult(odd, YES) && !SGBugsResult(odd, NO));
        CHECK(!SGGenieResult(odd) && !SGLyricsPlusResult(odd) && !SGDeezerResult(odd));
        CHECK(!SGLyricsPlusResult(@{@"type": @"Word", @"lyrics": @[odd]}));
        CHECK(!SGDeezerResult(deezerBody(@{@"synchronizedWordByWordLines": @[odd], @"synchronizedLines": @[odd], @"text": NSNull.null})));
    }
    NSString *huge = [@"x" stringByPaddingToLength:262145 withString:@"x" startingAtIndex:0];
    CHECK(!SGBugsResult(@{@"lyrics": huge}, NO) && !SGGenieResult(huge));
    CHECK(!SGLyricsPlusResult(@{@"type": @"Line", @"lyrics": @[@{@"time": @0, @"duration": @1, @"text": huge}]}));

    SGLyricsQuery *query = [SGLyricsQuery new];
    query.title = @"Made up"; query.artist = @"Singer feat. Guest"; query.seconds = 200;
    __block NSUInteger calls = 0, plain = 0;
    __block SGLyricsResult *got;
    sg_sourceAnswer = ^id(NSURL *url, NSDictionary *headers, NSData *body, NSInteger *status) {
        if ([url.host isEqualToString:@"m.bugs.co.kr"]) return @{@"list": @[
            @{@"track_id": @1, @"track_title": @"Other", @"artists": @[@{@"artist_nm": @"Singer"}]},
            @{@"track_id": @2, @"track_title": @"Made up", @"artists": @[@{@"artist_nm": @"Other"}]},
            @{@"track_id": @3, @"track_title": @"Made up", @"len": @"03:25", @"artists": @[@{@"artist_nm": @"Singer"}]},
            @{@"track_id": @4, @"track_title": @"Made up", @"len": @"03:24", @"mvs": @[@{@"len": @"00:10"}], @"artists": @[@{@"artist_nm": @"Singer"}]}]};
        CHECK([url.path hasSuffix:@"/4"]);
        if ([url.path containsString:@"/T/"]) return @{@"lyrics": @"invalid"};
        plain++; return @{@"lyrics": @"Made up words"};
    };
    SGBugsAsk(query, ^(SGLyricsResult *r) { CHECK(NSThread.isMainThread); got = r; calls++; });
    CHECK(calls == 1 && plain == 1 && got && !got.synced);
    sg_sourceAnswer = ^id(NSURL *url, NSDictionary *headers, NSData *body, NSInteger *status) {
        CHECK([headers[@"User-Agent"] isEqualToString:SGLyricsBrowserAgent]);
        if ([url.host isEqualToString:@"www.genie.co.kr"]) return @"<tr class='list' songid='1'><a class='title ellipsis' title='Made up'>x</a></tr>"
            "<tr class='list' songid='2'><a class='title ellipsis' title='Other'>x</a><a class='artist ellipsis'>Singer</a></tr>"
            "<tr class='list' songid='3'><a class='title ellipsis' title='Made&#32;up'>x</a><a class='artist ellipsis'><span>Singer</span></a></tr>";
        CHECK([param(url, @"songid") isEqualToString:@"3"] && [headers[@"Referer"] isEqualToString:@"https://www.genie.co.kr/"]);
        return @"null({\"8700\":\"Made up\"})";
    };
    calls = 0;
    SGGenieAsk(query, ^(SGLyricsResult *r) { got = r; calls++; });
    CHECK(calls == 1 && got.synced && got.karaokeLines.firstObject.start == 8700);
    __block NSUInteger plusRequests = 0;
    sg_sourceAnswer = ^id(NSURL *url, NSDictionary *headers, NSData *body, NSInteger *status) {
        CHECK([param(url, @"duration") isEqualToString:@"200.000"]);
        plusRequests++;
        if ([url.host isEqualToString:@"lyricsplus.prjktla.my.id"]) { *status = 503; return nil; }
        CHECK([url.host isEqualToString:@"lyrics.geeked.wtf"]); return plus;
    };
    calls = 0;
    SGLyricsPlusAsk(query, ^(SGLyricsResult *r) { got = r; calls++; });
    CHECK(calls == 1 && plusRequests == 2 && got.wordTimed);

    __block NSUInteger logins = 0, lyricsRequests = 0;
    __block BOOL refuse = YES;
    sg_sourceAnswer = ^id(NSURL *url, NSDictionary *headers, NSData *body, NSInteger *status) {
        if ([url.host isEqualToString:@"api.deezer.com"]) {
            CHECK(!headers[@"Cookie"] && !headers[@"Authorization"] && !body);
            return @{@"data": @[
                @{@"id": @1, @"title": @"Other", @"artist": @{@"name": @"Singer"}},
                @{@"id": @2, @"title": @"Made up", @"artist": @{@"name": @"Other"}},
                @{@"id": @3, @"title": @"Made up", @"duration": @205, @"artist": @{@"name": @"Singer"}},
                @{@"id": @4, @"title": @"Made up", @"duration": @204, @"artist": @{@"name": @"Singer"}}]};
        }
        if ([url.host isEqualToString:@"auth.deezer.com"]) {
            CHECK([headers[@"Cookie"] isEqualToString:@"arl=made-up-cookie"] && body && !body.length);
            logins++; return @{@"jwt": [NSString stringWithFormat:@"fake.token.%lu", (unsigned long)logins]};
        }
        CHECK([url.host isEqualToString:@"pipe.deezer.com"] && !headers[@"Cookie"] && headers[@"Authorization"]);
        NSDictionary *request = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
        CHECK([request[@"variables"][@"trackId"] isEqualToString:@"4"]);
        lyricsRequests++;
        if (refuse) return @{@"errors": @[@{@"extensions": @{@"code": @"UNAUTHENTICATED"}}]};
        return deezer;
    };
    calls = 0; NSUInteger requests = sg_sourceRequests;
    SGDeezerAskWith(nil, query, ^(SGLyricsResult *r) { got = r; calls++; });
    CHECK(calls == 1 && !got && sg_sourceRequests == requests);
    SGDeezerAskWith(@"bad;cookie", query, ^(SGLyricsResult *r) { CHECK(!r); });
    CHECK(sg_sourceRequests == requests);
    calls = 0;
    SGDeezerAskWith(@"made-up-cookie", query, ^(SGLyricsResult *r) { got = r; calls++; });
    CHECK(calls == 1 && !got && logins == 2 && lyricsRequests == 2);
    refuse = NO;
    SGDeezerAskWith(@"made-up-cookie", query, ^(SGLyricsResult *r) { got = r; });
    CHECK(got.wordTimed && logins == 3);
    SGDeezerAskWith(@"made-up-cookie", query, ^(SGLyricsResult *r) { got = r; });
    CHECK(got.wordTimed && logins == 3 && lyricsRequests == 4);

    // An HTTP auth failure refreshes once and still answers the original ask only once.
    id (^previousAnswer)(NSURL *, NSDictionary *, NSData *, NSInteger *) = sg_sourceAnswer;
    __block BOOL expired = YES;
    sg_sourceAnswer = ^id(NSURL *url, NSDictionary *headers, NSData *body, NSInteger *status) {
        if (expired && [url.host isEqualToString:@"pipe.deezer.com"]) { expired = NO; *status = 401; return nil; }
        if ([url.host isEqualToString:@"api.deezer.com"]) CHECK([param(url, @"q") isEqualToString:@"track:\"Made up\" artist:\"Singer\""]);
        return previousAnswer(url, headers, body, status);
    };
    query.title = @"\"Made up\"";
    calls = 0;
    SGDeezerAskWith(@"made-up-cookie", query, ^(SGLyricsResult *r) { got = r; calls++; });
    CHECK(calls == 1 && got.wordTimed && logins == 4);

    // Every source also completes its early miss on main when called from a worker queue.
    __block NSUInteger finished = 0;
    SGLyricsQuery *empty = [SGLyricsQuery new];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        void (^done)(SGLyricsResult *) = ^(SGLyricsResult *r) { CHECK(NSThread.isMainThread && !r); finished++; };
        SGBugsAsk(empty, done);
        SGGenieAsk(empty, done);
        SGLyricsPlusAsk(empty, done);
        SGDeezerAskWith(nil, empty, done);
    });
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:2];
    while (finished < 4 && until.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    CHECK(finished == 4);
    printf("Bugs, Genie, LyricsPlus, Deezer: parser, matching, fallback, auth and main-queue checks passed\n");
}

int main(int argc, char **argv) {
    @autoreleasepool {
        // Thai, Lao, Khmer and Burmese, long lines with no space, and Thai among Latin and brackets.
        checkSplit(@"ฉันรักเธอมากกว่าสิ่งใดในโลกนี้และจะอยู่เคียงข้างเธอตลอดไป", YES);
        checkSplit(@"วันนี้อากาศดีมากเราไปเดินเล่นที่สวนสาธารณะด้วยกันไหมนะที่รัก", YES);
        checkSplit(@"Baby(ที่รัก)ฉันคิดถึงเธอทุกวันทุกคืนไม่เคยลืมเลย,ok?", YES);
        checkSplit(@"ฉันรักเธอ, เธอรักฉัน... (ด้วยหัวใจ)", YES);
        CHECK([piecesOf(@"(ด้วยหัวใจ)").firstObject.text isEqualToString:@"(ด้วย"]);   // what comes before the first word stays with it
        checkSplit(@"ຂ້ອຍຮັກເຈົ້າຫຼາຍທີ່ສຸດໃນໂລກນີ້ແລະຈະຢູ່ນຳເຈົ້າຕະຫຼອດໄປ", NO);
        checkSplit(@"ខ្ញុំស្រលាញ់អ្នកខ្លាំងណាស់ហើយនឹងនៅជាមួយអ្នកជារៀងរហូត", NO);
        checkSplit(@"ကျွန်တော်မင်းကိုအရမ်းချစ်တယ်ထာဝရမင်းနဲ့အတူရှိနေမယ်", NO);
        CHECK(piecesOf(@"๏๚").count == 1);   // Thai punctuation alone: no word, one piece
        CHECK(piecesOf(@"hello world").count == 2 && !piecesOf(@"hello world")[1].joined);
        CHECK(piecesOf(@"日本語の歌").count == 5 && piecesOf(@"日本語の歌")[4].joined);
        NSArray<SGKaraokeWord *> *thai = piecesOf(@"ฉันรักเธอมากกว่าสิ่งใดในโลกนี้");
        CHECK(!thai[0].joined && thai[1].joined);

        // The keys the two catalogs are matched by.
        CHECK([SGLyricsMatchKey(@"晴天（Live版）") isEqualToString:SGLyricsMatchKey(@"晴天 (Live版)")]);
        CHECK([SGLyricsMatchKey(@"Hello,　World!") isEqualToString:@"helloworld"]);
        CHECK([SGLyricsMatchKey(@"《稻香》") isEqualToString:@"稻香"]);
        CHECK([SGLyricsLeadArtist(@"周杰伦 feat. 费玉清") isEqualToString:@"周杰伦"]);
        CHECK(SGLyricsSameArtist(@"周杰伦、费玉清", @"周杰伦 Feat. Someone") && !SGLyricsSameArtist(@"林俊杰", @"周杰伦"));
        CHECK(!SGLyricsSameArtist(@"", @"周杰伦") && !SGLyricsSameArtist(nil, @"x"));

        // KRC: pieces timed from their line's start, a spaced word's pieces run together, a syllable each
        // in Chinese, a piece of no length shown for 1 ms, a line ending at its last word when that is later.
        NSArray<SGKaraokeLine *> *lines = SGKuGouLines(packed(kKRC, @"krc1"));
        CHECK(lines.count == 3);
        CHECK([SGKaraokeLineText(lines[0]) isEqualToString:@"Hello world"] && lines[0].words.count == 2);
        CHECK(lines[0].words[0].start == 1000 && lines[0].words[0].end == 1800 && lines[0].words[1].start == 1800);
        CHECK(lines[0].start == 1000 && lines[0].end == 3000 && lines[0].timing == SGKaraokeTimingWords);
        CHECK(lines[1].words.count == 3 && [SGKaraokeLineText(lines[1]) isEqualToString:@"你好啊"]);
        CHECK(lines[1].words[1].joined && lines[1].words[2].start == 4800 && lines[1].words[2].end == 4801);
        CHECK(lines[2].end == 7300);
        CHECK(!SGKuGouLines(packed(kKRC, @"krc2")) && !SGKuGouLines(@"bm90IGtyYw==") && !SGKuGouLines(nil));
        CHECK(!SGKuGouLines(packed(@"[ar:only tags]", @"krc1")));

        // KuGou: the user uploads, another title, another singer, a length 21 s off and a candidate with
        // no key are passed over; the rest are tried closest in length first, three at most.
        NSArray *candidates = @[
            @{@"id": @"a", @"accesskey": @"k", @"product_from": @"ugc", @"song": @"晴天", @"singer": @"周杰伦", @"duration": @269000},
            @{@"id": @"b", @"accesskey": @"k", @"song": @"晴天 (Live)", @"singer": @"周杰伦", @"duration": @269000},
            @{@"id": @"c", @"accesskey": @"k", @"song": @"晴天", @"singer": @"Other", @"duration": @269000},
            @{@"id": @"d", @"accesskey": @"k", @"song": @"晴天", @"singer": @"周杰伦", @"duration": @290000},
            @{@"id": @"e", @"accesskey": @"k", @"song": @"晴天", @"singer": @"周杰伦", @"duration": @265000},
            @{@"id": @7, @"accesskey": @"k", @"song": @"晴天", @"singer": @"周杰伦", @"duration": @269500},
            @{@"id": @"g", @"accesskey": @"k", @"song": @"晴天", @"singer": @"周杰伦", @"duration": @262000},
            @{@"id": @"h", @"song": @"晴天", @"singer": @"周杰伦", @"duration": @270000},
            @{@"id": @"i", @"accesskey": @"k", @"song": @" 晴天！", @"singer": @"周杰伦、费玉清", @"duration": @"268000"},
        ];
        NSMutableArray<NSString *> *tried = [NSMutableArray array];
        __block NSString *keyword, *duration, *good = @"e";
        sg_answer = ^id(NSURL *url, id body) {
            if ([url.host isEqualToString:@"krcs.kugou.com"]) {
                keyword = param(url, @"keyword");
                duration = param(url, @"duration");
                return @{@"status": @200, @"candidates": candidates};
            }
            NSString *song = param(url, @"id");
            [tried addObject:song];
            if ([song isEqualToString:good]) return @{@"status": @200, @"content": packed(kKRC, @"krc1")};
            return [song isEqualToString:@"7"] ? @{@"status": @200, @"content": @"garbage"} : @{@"status": @404};
        };
        SGLyricsQuery *query = [SGLyricsQuery new];
        query.title = @"晴天";
        query.artist = @"周杰伦 feat. Someone";
        query.seconds = 269;
        __block SGLyricsResult *got = nil;
        SGKuGouAsk(query, ^(SGLyricsResult *result) { got = result; });
        CHECK([keyword isEqualToString:@"周杰伦 - 晴天"] && [duration isEqualToString:@"269000"]);
        CHECK([tried isEqualToArray:(@[@"7", @"i", @"e"])]);
        CHECK(got.synced && got.wordTimed && got.karaokeLines.count == 3 && got.texts.count == 3);
        [tried removeAllObjects];
        good = @"g";   // fourth in line: never asked
        got = [SGLyricsResult new];
        SGKuGouAsk(query, ^(SGLyricsResult *result) { got = result; });
        CHECK([tried isEqualToArray:(@[@"7", @"i", @"e"])] && !got);
        query.artist = @"";
        got = [SGLyricsResult new];
        [tried removeAllObjects];
        SGKuGouAsk(query, ^(SGLyricsResult *result) { got = result; });
        CHECK(!got && !tried.count);

        // QQ Music: the first result with the title, a singer and the length is taken, and its LRC read.
        NSString *lrc = @"[ti:x]\n[ar:y]\n[00:01.00]第一行\n[00:03.50]第二行\n";
        __block NSDictionary *asked = nil;
        sg_answer = ^id(NSURL *url, NSDictionary *body) {
            if (body[@"req"]) return @{@"req": @{@"data": @{@"body": @{@"song": @{@"list": @[
                @{@"title": @"晴天", @"interval": @269, @"singer": @[@{@"name": @"Someone Else"}], @"id": @1},
                @{@"title": @"晴天", @"interval": @300, @"singer": @[@{@"name": @"周杰伦"}], @"id": @2},
                @{@"title": @"雨天", @"interval": @269, @"singer": @[@{@"name": @"周杰伦"}], @"id": @3},
                @{@"songname": @"晴天", @"interval": @270, @"singer": @[@{@"name": @"x"}, @{@"name": @"周杰伦"}], @"id": @97773},
            ]}}}}};
            asked = body[@"music.musichallSong.PlayLyricInfo.GetPlayLyricInfo"][@"param"];
            NSString *encoded = [[lrc dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
            return @{@"music.musichallSong.PlayLyricInfo.GetPlayLyricInfo": @{@"data": @{@"lyric": encoded}}};
        };
        query.artist = @"周杰伦";
        got = nil;
        SGQQMusicAsk(query, ^(SGLyricsResult *result) { got = result; });
        CHECK([asked[@"songID"] isEqual:@97773] && [asked[@"qrc"] isEqual:@0] && [asked[@"crypt"] isEqual:@0]);
        CHECK(got.synced && !got.wordTimed && got.karaokeLines.count == 2 && got.karaokeLines[1].start == 3500);
        query.seconds = 200;   // no recording that long: nothing asked for lyrics
        asked = nil;
        got = [SGLyricsResult new];
        SGQQMusicAsk(query, ^(SGLyricsResult *result) { got = result; });
        CHECK(!got && !asked);

        checkNewSources();
        checkReadingAndSearch();

        for (int i = 1; i < argc; i++) checkLive(@(argv[i]));
        printf("lyrics-sources: all checks passed\n");
    }
    return 0;
}
