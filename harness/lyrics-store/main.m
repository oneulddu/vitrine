#import <Foundation/Foundation.h>
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Lyrics/LyricsStore.h"
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #c); exit(1); } } while (0)

static SGKaraokeLine *line(NSString *text, NSInteger start) {
    SGKaraokeWord *a = [SGKaraokeWord new], *b = [SGKaraokeWord new];
    a.text = text; a.start = start; a.end = start + 300;
    b.text = @"!"; b.start = start + 300; b.end = start + 500; b.joined = YES;
    SGKaraokeLine *l = [SGKaraokeLine new];
    l.words = @[a, b]; l.start = start; l.end = start + 500;
    l.voice = @"v2"; l.align = SGKaraokeAlignTrailing; l.timing = SGKaraokeTimingWords;
    return l;
}

static void pump(BOOL (^ready)(void)) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!ready() && until.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
    CHECK(ready());
}

static unsigned long long size(void) {
    __block BOOL done = NO; __block unsigned long long bytes;
    SGLyricsStoreSize(^(unsigned long long n) { CHECK(NSThread.isMainThread); bytes = n; done = YES; });
    pump(^BOOL { return done; });
    return bytes;
}

static NSArray *load(NSString *track, NSString **credit) {
    __block BOOL done = NO; __block NSArray *result; __block NSString *provider;
    SGLyricsStoreLoad(track, ^(NSArray *lines, NSString *name) {
        CHECK(NSThread.isMainThread); result = lines; provider = name; done = YES;
    });
    pump(^BOOL { return done; });
    if (credit) *credit = provider;
    return result;
}

static NSArray<NSURL *> *files(NSURL *dir) {
    return [NSFileManager.defaultManager contentsOfDirectoryAtURL:dir includingPropertiesForKeys:nil options:0 error:nil] ?: @[];
}

// Every fixture is a unique directory; it is the only tree this test deletes.
static NSURL *temp(void) {
    NSString *pattern = [NSTemporaryDirectory() stringByAppendingPathComponent:@"vitrine-lyrics-XXXXXX"];
    char *path = strdup(pattern.fileSystemRepresentation);
    CHECK(mkdtemp(path));
    NSURL *url = [NSURL fileURLWithPath:[NSFileManager.defaultManager stringWithFileSystemRepresentation:path length:strlen(path)] isDirectory:YES];
    free(path);
    return url;
}

static void ageAll(NSURL *dir, NSTimeInterval time) {
    for (NSURL *url in files(dir)) CHECK([NSFileManager.defaultManager setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSince1970:time]}
        ofItemAtPath:url.path error:nil]);
}

int main(void) {
    @autoreleasepool {
        SGKaraokeLine *lead = line(@"Hello", 1000);
        lead.backing = line(@"Oh", 1100); lead.pronunciation = line(@"Hel-lo", 1000);
        lead.note = @"A reference"; lead.translation = @"안녕"; lead.translationMade = YES;
        lead.backing.translation = @"오";
        SGKaraokeLine *ai = line(@"World", 2000);
        ai.pronunciation = line(@"Generated", 2000); ai.pronunciationMade = YES;
        NSArray *original = @[lead, ai];
        NSDictionary *record = SGLyricsStoreEncode(original, @"Fixture provider");
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:record format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        CHECK(data && !record[@"lines"][0][@"translation"] && !record[@"lines"][0][@"translationMade"]);
        CHECK(!record[@"lines"][0][@"backing"][@"translation"] && !record[@"lines"][1][@"pronunciation"]);
        NSString *credit;
        NSArray<SGKaraokeLine *> *round = SGLyricsStoreDecode([NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:nil], &credit);
        CHECK(round.count == 2 && [credit isEqual:@"Fixture provider"]);
        SGKaraokeLine *decoded = round[0];
        CHECK([decoded.words[0].text isEqual:@"Hello"] && decoded.words[0].start == 1000 && decoded.words[0].end == 1300);
        CHECK(decoded.words[1].joined && !decoded.words[0].joined && decoded.start == 1000 && decoded.end == 1500);
        CHECK([decoded.voice isEqual:@"v2"] && decoded.align == SGKaraokeAlignTrailing && decoded.timing == SGKaraokeTimingWords);
        CHECK([decoded.backing.words[0].text isEqual:@"Oh"] && [decoded.pronunciation.words[0].text isEqual:@"Hel-lo"]);
        CHECK([decoded.note isEqual:@"A reference"] && !decoded.translation && !decoded.translationMade);
        CHECK(!round[1].pronunciation && round[1].pronunciationMade);
        CHECK(SGLyricsStoreDecode(SGLyricsStoreEncode(@[line(@"No credit", 0)], nil), &credit) && !credit);
        NSMutableDictionary *bad = [record mutableCopy]; bad[@"v"] = @2;
        CHECK(!SGLyricsStoreDecode(bad, &credit) && !credit);
        for (id garbage in @[@"garbage", @1, NSNull.null, @[], @{}, @{@"v": @1, @"lines": @[@"bad"]},
                              @{@"v": @1, @"lines": @[], @"credit": @7}]) CHECK(!SGLyricsStoreDecode(garbage, NULL));
        for (NSString *key in @[@"words", @"start", @"end", @"align", @"timing", @"voice", @"note", @"backing", @"pronunciation", @"pronunciationMade"]) {
            NSMutableDictionary *badLine = [record[@"lines"][0] mutableCopy]; badLine[key] = NSNull.null;
            CHECK(!SGLyricsStoreDecode(@{@"v": @1, @"lines": @[badLine]}, NULL));
        }
        NSMutableDictionary *badWord = [record[@"lines"][0][@"words"][0] mutableCopy];
        badWord[@"joined"] = @2;
        NSMutableDictionary *badLine = [record[@"lines"][0] mutableCopy]; badLine[@"words"] = @[badWord];
        CHECK(!SGLyricsStoreDecode(@{@"v": @1, @"lines": @[badLine]}, NULL));
        badLine[@"words"] = record[@"lines"][0][@"words"]; badLine[@"timing"] = @99;
        CHECK(!SGLyricsStoreDecode(@{@"v": @1, @"lines": @[badLine]}, NULL));
        badLine[@"timing"] = @0; badLine[@"start"] = @(NAN);
        CHECK(!SGLyricsStoreDecode(@{@"v": @1, @"lines": @[badLine]}, NULL));

        NSMutableArray *typical = [NSMutableArray array];
        for (NSInteger i = 0; i < 40; i++) {
            SGKaraokeLine *l = line(@"We sing together in the evening", i * 4000);
            NSMutableArray *words = [NSMutableArray array];
            NSInteger j = 0;
            for (NSString *text in [@"We sing together in the evening" componentsSeparatedByString:@" "]) {
                SGKaraokeWord *w = [SGKaraokeWord new];
                w.text = text; w.start = l.start + j * 500; w.end = w.start + 500; j++; [words addObject:w];
            }
            l.words = words; l.end = l.start + 3000; [typical addObject:l];
        }
        NSData *typicalData = [NSPropertyListSerialization dataWithPropertyList:SGLyricsStoreEncode(typical, @"Fixture provider")
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        printf("Typical fixture: 40 lines / 240 timed words, %lu bytes (binary plist)\n", (unsigned long)typicalData.length);

        NSURL *dir = temp();
        SGLyricsStoreConfigureForTests(dir, 1000, 30 * 1024 * 1024);
        SGLyricsStoreSave(@"../../track", original, @"Fixture provider");
        CHECK(size() == data.length && files(dir).count == 1);
        NSURL *file = files(dir).firstObject;
        CHECK(file.lastPathComponent.length == 70 && [file.pathExtension isEqual:@"plist"]);
        NSData *stored = [NSData dataWithContentsOfURL:file];
        CHECK(stored.length >= 8 && memcmp(stored.bytes, "bplist00", 8) == 0);
        NSNumber *excluded; CHECK([dir getResourceValue:&excluded forKey:NSURLIsExcludedFromBackupKey error:nil] && excluded.boolValue);
        ageAll(dir, 100);
        CHECK(load(@"../../track", &credit).count == 2 && [credit isEqual:@"Fixture provider"]);
        NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:file.path error:nil];
        CHECK([attrs[NSFileModificationDate] timeIntervalSince1970] > 100);
        CHECK(!load(@"missing", NULL));
        CHECK([@"garbage" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:nil]);
        CHECK(!load(@"../../track", NULL));
        SGLyricsStoreDelete(@"../../track"); CHECK(size() == 0);

        // Count cap: five writes cross four; oldest two go, leaving newest three (90%).
        NSArray *small = @[line(@"Same", 0)];
        SGLyricsStoreConfigureForTests(dir, 4, 1024 * 1024);
        for (NSUInteger i = 0; i < 5; i++) {
            SGLyricsStoreSave(@(i).stringValue, small, nil); size();
            if (i == 0) ageAll(dir, 100);
            if (i == 1) {
                for (NSURL *url in files(dir)) {
                    NSDictionary *a = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
                    if ([a[NSFileModificationDate] timeIntervalSince1970] > 100)
                        CHECK([NSFileManager.defaultManager setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSince1970:200]} ofItemAtPath:url.path error:nil]);
                }
            }
        }
        CHECK(files(dir).count == 3 && !load(@"0", NULL) && !load(@"1", NULL));
        CHECK(load(@"2", NULL) && load(@"3", NULL) && load(@"4", NULL));
        __block BOOL cleared = NO;
        SGLyricsStoreDeleteAll(^(unsigned long long remaining) { CHECK(remaining == 0); cleared = YES; });
        pump(^BOOL { return cleared; });
        CHECK(![NSFileManager.defaultManager fileExistsAtPath:dir.path]);

        // Byte cap alone: three equal records cross 2.5 records; newest two fit 90%.
        NSUInteger unit = [NSPropertyListSerialization dataWithPropertyList:SGLyricsStoreEncode(small, nil)
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil].length;
        SGLyricsStoreConfigureForTests(dir, 100, unit * 5 / 2);
        SGLyricsStoreSave(@"old", small, nil); CHECK(size() == unit); ageAll(dir, 100);
        SGLyricsStoreSave(@"middle", small, nil); CHECK(size() == unit * 2);
        SGLyricsStoreSave(@"new", small, nil); CHECK(size() == unit * 2);
        CHECK(files(dir).count == 2 && !load(@"old", NULL) && load(@"middle", NULL) && load(@"new", NULL));
        CHECK(size() <= unit * 5 / 2 * 9 / 10);
        cleared = NO;
        SGLyricsStoreDeleteAll(^(unsigned long long remaining) { CHECK(!remaining); cleared = YES; });
        pump(^BOOL { return cleared; });
        puts("lyrics-store: all checks passed");
    }
    return 0;
}
