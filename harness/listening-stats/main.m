// Runs SGPlayLog.m on the Mac against synthetic export files, loose and zipped, and checks what the stats
// page would read out. Exits non-zero when a check fails.
//
//     ./build.sh && build/listening-stats
#import <Foundation/Foundation.h>
#import "Shared/ListeningStats/SGPlayLog.h"

static int failures = 0;
#define CHECK(cond, ...) do { if (cond) printf("ok    "); else { printf("FAIL  "); failures++; } printf(__VA_ARGS__); printf("\n"); } while (0)

static NSData *json(id object) {
    return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
}

static NSString *stamp(int64_t t, BOOL extended) {
    NSDateFormatter *f = [NSDateFormatter new];
    f.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = extended ? @"yyyy-MM-dd'T'HH:mm:ss'Z'" : @"yyyy-MM-dd HH:mm";
    return [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:t]];
}

static NSDictionary *extendedRow(int64_t end, int64_t ms, NSString *title, NSString *artist, NSString *album) {
    return @{@"ts": stamp(end, YES), @"platform": @"ios", @"ms_played": @(ms), @"conn_country": @"CZ",
             @"master_metadata_track_name": title ?: (id)NSNull.null, @"master_metadata_album_artist_name": artist ?: (id)NSNull.null,
             @"master_metadata_album_album_name": album ?: (id)NSNull.null,
             @"spotify_track_uri": title ? [@"spotify:track:" stringByAppendingString:title] : (id)NSNull.null,
             @"episode_name": NSNull.null, @"spotify_episode_uri": NSNull.null, @"reason_end": @"trackdone"};
}

static NSDictionary *basicRow(int64_t end, int64_t ms, NSString *title, NSString *artist) {
    return @{@"endTime": stamp(end, NO), @"artistName": artist, @"trackName": title, @"msPlayed": @(ms)};
}

static SGPlay *play(int64_t end, int64_t ms, NSString *title, NSString *artist, NSString *album) {
    SGPlay *p = [SGPlay new];
    p.end = end; p.ms = ms; p.title = title; p.artist = artist; p.album = album ?: @""; p.uri = @"";
    return p;
}

static void zip(NSString *dir, NSString *out, NSArray<NSString *> *names, BOOL stored) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/zip"];
    task.currentDirectoryURL = [NSURL fileURLWithPath:dir];
    NSMutableArray *args = [NSMutableArray arrayWithObjects:@"-q", stored ? @"-0" : @"-9", out, nil];
    [args addObjectsFromArray:names];
    task.arguments = args;
    [task launchAndReturnError:nil];
    [task waitUntilExit];
}

static double since(NSDate *start) {
    return -start.timeIntervalSinceNow * 1000;
}

static NSDate *date(NSString *iso) {
    return [[NSISO8601DateFormatter new] dateFromString:iso];
}

static SGPlay *dated(NSString *iso, int64_t ms) {
    return play((int64_t)date(iso).timeIntervalSince1970, ms, @"Calendar song", @"Artist", @"Album");
}

static void calendarChecks(void) {
    NSCalendar *ny = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    ny.timeZone = [NSTimeZone timeZoneWithName:@"America/New_York"];
    NSArray *spring = @[dated(@"2026-03-07T23:30:00-05:00", 20000), dated(@"2026-03-08T23:30:00-04:00", 60000),
                        dated(@"2026-03-09T00:30:00-04:00", 120000), dated(@"2026-03-08T12:00:00-04:00", 60000)];
    SGListeningStreaks *s = SGStreaks(spring, date(@"2026-03-09T12:00:00-04:00"), ny);
    CHECK(s.current == 3 && s.best == 3, "streak: spring DST, duplicate local day and counted short play = 3 days");
    s = SGStreaks(spring, date(@"2026-03-10T12:00:00-04:00"), ny);
    CHECK(s.current == 3 && s.best == 3, "streak: yesterday remains current when today has no play");
    s = SGStreaks(spring, date(@"2026-03-11T00:00:00-04:00"), ny);
    CHECK(s.current == 0 && s.best == 3, "streak: missing yesterday ends current but keeps best");
    s = SGStreaks(@[], date(@"2026-03-09T12:00:00-04:00"), ny);
    CHECK(s.current == 0 && s.best == 0, "streak: empty history");
    NSArray *fall = @[dated(@"2026-10-31T23:45:00-04:00", 60000), dated(@"2026-11-01T01:30:00-04:00", 60000),
                      dated(@"2026-11-01T01:30:00-05:00", 120000), dated(@"2026-11-02T00:05:00-05:00", 30000)];
    s = SGStreaks(fall, date(@"2026-11-02T12:00:00-05:00"), ny);
    CHECK(s.current == 3 && s.best == 3, "streak: fall DST repeated hour counts as one day");
    NSArray<SGStatEntry *> *hours = SGHourlyStats(fall, 0, ny);
    CHECK(hours.count == 24 && hours[1].plays == 2 && hours[1].ms == 180000 && hours[0].plays == 1 && hours[23].plays == 1,
          "hours: both fall 01:30 plays combine; midnight and 23:45 use local hours");
    hours = SGHourlyStats(fall, (int64_t)date(@"2026-11-01T01:30:00-05:00").timeIntervalSince1970, ny);
    CHECK(hours[1].plays == 1 && hours[1].ms == 120000 && hours[23].plays == 0, "hours: selected period includes exact cutoff only once");
    hours = SGHourlyStats(@[dated(@"2026-03-08T01:59:00-05:00", 60000), dated(@"2026-03-08T03:00:00-04:00", 90000)], 0, ny);
    CHECK(hours[1].plays == 1 && hours[2].plays == 0 && hours[3].ms == 90000, "hours: missing spring hour stays empty");
    hours = SGHourlyStats(@[], 0, ny);
    CHECK(hours.count == 24 && hours[0].plays == 0 && hours[23].ms == 0, "hours: empty history still has 24 zero buckets");
    NSArray *leap = @[dated(@"2024-02-28T23:00:00-05:00", 60000), dated(@"2024-02-29T23:00:00-05:00", 60000),
                      dated(@"2024-03-01T01:00:00-05:00", 60000), dated(@"2024-03-04T01:00:00-05:00", 60000),
                      dated(@"2024-03-05T01:00:00-05:00", 60000)];
    s = SGStreaks(leap, date(@"2024-03-04T12:00:00-05:00"), ny);
    CHECK(s.current == 1 && s.best == 3, "streak: leap day/month boundary, gap, future day ignored");
    NSArray *year = @[dated(@"2025-12-31T23:59:00-05:00", 60000), dated(@"2026-01-01T00:01:00-05:00", 60000)];
    s = SGStreaks(year, date(@"2026-01-01T12:00:00-05:00"), ny);
    CHECK(s.current == 2 && s.best == 2, "streak: year boundary uses calendar days, not UTC days");
    NSCalendar *buddhist = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierBuddhist];
    buddhist.timeZone = ny.timeZone;
    s = SGStreaks(year, date(@"2026-01-01T12:00:00-05:00"), buddhist);
    CHECK(s.current == 2 && s.best == 2, "streak: non-Gregorian calendar");
    NSCalendar *kathmandu = [ny copy];
    kathmandu.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Kathmandu"];
    hours = SGHourlyStats(@[dated(@"2026-01-01T18:30:00Z", 20000)], 0, kathmandu);
    CHECK(hours[0].plays == 1 && hours[0].ms == 20000, "hours: fractional timezone and counted short track");
    NSCalendar *brazil = [ny copy];
    brazil.timeZone = [NSTimeZone timeZoneWithName:@"America/Sao_Paulo"];
    NSArray *midnightDST = @[dated(@"2018-11-03T12:00:00-03:00", 60000), dated(@"2018-11-04T12:00:00-02:00", 60000),
                             dated(@"2018-11-05T12:00:00-02:00", 60000)];
    s = SGStreaks(midnightDST, date(@"2018-11-06T12:00:00-02:00"), brazil);
    CHECK(s.current == 3 && s.best == 3, "streak: timezone skipping midnight at DST start");
}

static void localHistoryChecks(NSString *dir, NSArray<SGPlay *> *existing) {
    SGPlay *shortPlay = play(1700000001, 12500, @"짧은 곡 🎵", @"가수", @"");
    shortPlay.uri = @"spotify:local:short";
    NSArray *records = [existing arrayByAddingObject:shortPlay];
    NSError *error;
    NSData *data = SGHistoryJSON(records, &error);
    NSArray<SGPlay *> *decoded = SGPlaysFromExport(data);
    BOOL equal = data && !error && decoded.count == records.count;
    for (NSUInteger i = 0; equal && i < records.count; i++) {
        SGPlay *a = records[i], *b = decoded[i];
        equal = a.end == b.end && a.ms == b.ms && [a.uri isEqual:b.uri] && [a.title isEqual:b.title] &&
                [a.artist isEqual:b.artist] && [a.album isEqual:b.album];
    }
    CHECK(equal && decoded.lastObject.ms == 12500, "Vitrine JSON: all six fields round-trip, including Unicode and counted short tracks");
    SGPlay *escaped = play(1700000002, 1000, @"Tab\tquote\"newline\n", @"Artist", @"Album");
    CHECK([SGPlaysFromExport(SGHistoryJSON(@[escaped], nil)).firstObject.title isEqual:escaped.title], "Vitrine JSON: escaped text round-trips");
    CHECK(SGPlaysFromExport(SGHistoryJSON(@[], nil)).count == 0, "Vitrine JSON: empty versioned history is recognized");
    SGPlay *nearA = play(1700000100, 40000, @"Repeat", @"Artist", @"Album");
    SGPlay *nearB = play(1700000160, 41000, @"Repeat", @"Artist", @"Album");
    NSArray *nearby = SGPlaysFromExport(SGHistoryJSON(@[nearA, nearB], nil));
    SGPlayLog *nearLog = [[SGPlayLog alloc] initWithPath:[dir stringByAppendingPathComponent:@"nearby.tsv"]];
    CHECK([nearLog merge:nearby] == 2 && [nearLog merge:nearby] == 0 && nearLog.plays.count == 2,
          "Vitrine JSON: distinct plays 60 seconds apart both restore, while an exact second import adds nothing");
    NSString *path = [dir stringByAppendingPathComponent:@"local-roundtrip.tsv"];
    SGPlayLog *log = [[SGPlayLog alloc] initWithPath:path];
    CHECK([log merge:decoded] == records.count && [log merge:decoded] == 0, "Vitrine JSON: merge once, duplicate import adds nothing");
    NSData *before = [NSData dataWithContentsOfFile:path];
    [log merge:@[play(1900000000, 40000, @"Another", @"Artist", @"Album")]];
    NSData *after = [NSData dataWithContentsOfFile:path];
    CHECK(after.length > before.length && [[after subdataWithRange:NSMakeRange(0, before.length)] isEqual:before], "TSV: importing appends without rewriting any existing byte");
    SGPlayLog *reopened = [[SGPlayLog alloc] initWithPath:path];
    CHECK(reopened.plays.count == records.count + 1 && reopened.plays[records.count - 1].ms == 12500, "TSV: imported local short play persists after reload");
    NSMutableDictionary *root = [[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] mutableCopy];
    root[@"version"] = @2;
    CHECK(SGPlaysFromExport(json(root)) == nil, "Vitrine JSON: unknown version rejected");
    root[@"version"] = @YES;
    CHECK(SGPlaysFromExport(json(root)) == nil, "Vitrine JSON: boolean version rejected");
    root[@"version"] = @1; root[@"format"] = @"other.history";
    CHECK(SGPlaysFromExport(json(root)) == nil, "Vitrine JSON: unknown format rejected");
    root[@"format"] = @"vitrine.listening-history";
    NSMutableDictionary *row = [root[@"plays"][0] mutableCopy];
    for (id bad in @[@"123", @YES, @(-1), @1.5, NSNull.null, @18446744073709551615ULL]) {
        row[@"ms"] = bad; root[@"plays"] = @[row];
        CHECK(SGPlaysFromExport(json(root)) == nil, "Vitrine JSON: malformed milliseconds rejected (%s)", [[bad description] UTF8String]);
    }
    row[@"ms"] = @40000; row[@"title"] = NSNull.null;
    CHECK(SGPlaysFromExport(json(root)) == nil, "Vitrine JSON: malformed text rejects whole file");
    root[@"plays"] = @[@1];
    CHECK(SGPlaysFromExport(json(root)) == nil, "Vitrine JSON: non-object row rejected");
    [root removeObjectForKey:@"plays"];
    CHECK(SGPlaysFromExport(json(root)) == nil, "Vitrine JSON: missing plays rejected");

    NSString *folder = [dir stringByAppendingPathComponent:@"selected"];
    NSString *nested = [folder stringByAppendingPathComponent:@"nested"];
    [NSFileManager.defaultManager createDirectoryAtPath:nested withIntermediateDirectories:YES attributes:nil error:nil];
    [data writeToFile:[nested stringByAppendingPathComponent:@"history.json"] atomically:YES];
    [data writeToFile:[folder stringByAppendingPathComponent:@".hidden.json"] atomically:YES];
    [data writeToFile:[folder stringByAppendingPathComponent:@"ignore.txt"] atomically:YES];
    [@"invalid" writeToFile:[folder stringByAppendingPathComponent:@"bad.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *outside = [dir stringByAppendingPathComponent:@"outside.json"];
    [data writeToFile:outside atomically:YES];
    [NSFileManager.defaultManager createSymbolicLinkAtPath:[folder stringByAppendingPathComponent:@"escape.json"] withDestinationPath:outside error:nil];
    [NSFileManager.defaultManager createSymbolicLinkAtPath:[folder stringByAppendingPathComponent:@"escape-folder"] withDestinationPath:dir error:nil];
    NSString *deep = folder;
    for (NSUInteger i = 0; i < 9; i++) deep = [deep stringByAppendingPathComponent:@"deeper"];
    [NSFileManager.defaultManager createDirectoryAtPath:deep withIntermediateDirectories:YES attributes:nil error:nil];
    [data writeToFile:[deep stringByAppendingPathComponent:@"too-deep.json"] atomically:YES];
    NSString *large = [folder stringByAppendingPathComponent:@"too-large.json"];
    [NSFileManager.defaultManager createFileAtPath:large contents:nil attributes:nil];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:large];
    [handle truncateAtOffset:65 * 1024 * 1024 error:nil]; [handle closeAndReturnError:nil];
    SGHistoryImport *import = SGReadHistoryURLs(@[[NSURL fileURLWithPath:folder]]);
    CHECK(import.files == 1 && import.plays.count == records.count && import.skipped >= 4,
          "folder: nested JSON only, hidden/irrelevant/symlink/oversized/deep/malformed entries excluded (%lu files, %lu skips)",
          (unsigned long)import.files, (unsigned long)import.skipped);
    import = SGReadHistoryURLs(@[[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:@"escape.json"]]]);
    CHECK(import.files == 0 && import.skipped == 1, "folder: explicitly selected symlink is refused");

    SGPlayLog *asyncLog = [[SGPlayLog alloc] initWithPath:path];
    __block NSUInteger completions = 0;
    [asyncLog loadWithCompletion:^{ completions++; }];
    [asyncLog loadWithCompletion:^{ completions++; }];
    [asyncLog record:play(1900000500, 10000, @"During load", @"Recorder", @"")];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (completions < 2 && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    CHECK(completions == 2 && asyncLog.plays.count == records.count + 2 && [asyncLog.plays.lastObject.title isEqual:@"During load"],
          "async TSV load: both callbacks complete, concurrent recording included exactly once");
    CHECK([[SGPlayLog alloc] initWithPath:path].plays.count == asyncLog.plays.count, "async TSV load: memory and append-only file agree");
    SGPlayLog *erasedDuringLoad = [[SGPlayLog alloc] initWithPath:path];
    __block BOOL done = NO;
    [erasedDuringLoad loadWithCompletion:^{ done = YES; }];
    [erasedDuringLoad erase];
    [erasedDuringLoad record:play(1900000600, 20000, @"After erase", @"Recorder", @"")];
    deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!done && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    CHECK(done && erasedDuringLoad.plays.count == 1 && [erasedDuringLoad.plays.firstObject.title isEqual:@"After erase"],
          "async TSV load: erase during loading cannot resurrect old records");
    NSString *corruptPath = [dir stringByAppendingPathComponent:@"corrupt.tsv"];
    uint8_t invalidUTF8[] = {0xff, 0xff};
    [[NSData dataWithBytes:invalidUTF8 length:2] writeToFile:corruptPath atomically:YES];
    SGPlayLog *corrupt = [[SGPlayLog alloc] initWithPath:corruptPath];
    done = NO;
    [corrupt loadWithCompletion:^{ done = YES; }];
    deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!done && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    CHECK(done && corrupt.loadError != nil, "async TSV load: corrupt encoding is an explicit error, not empty history");
}

int main(void) {
    @autoreleasepool {
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"listening-stats-harness"];
        NSString *exportDir = [dir stringByAppendingPathComponent:@"export"];
        [NSFileManager.defaultManager removeItemAtPath:dir error:nil];
        [NSFileManager.defaultManager createDirectoryAtPath:[exportDir stringByAppendingPathComponent:@"__MACOSX"] withIntermediateDirectories:YES attributes:nil error:nil];

        // A fixed "now" on a whole minute, so the basic export's minute stamps land exactly.
        int64_t now = 1790000000 - 1790000000 % 60, day = 86400;

        // Extended: Song A twice and Song B 3 days ago, Song C 20 days ago, Song D 200 days ago, Song A
        // 2 years ago; then a podcast row (nulls), a 10 s skip and a row without a ts.
        NSArray *extended = @[
            extendedRow(now - 3 * day, 200000, @"Song A", @"Artist 1", @"Album X"),
            extendedRow(now - 3 * day + 300, 180000, @"Song A", @"Artist 1", @"Album X"),
            extendedRow(now - 3 * day + 600, 60000, @"Song B", @"Artist 2", @"Album Y"),
            extendedRow(now - 20 * day, 240000, @"Song C", @"Artist 1", @"Album Z"),
            extendedRow(now - 200 * day, 210000, @"Song D", @"Artist 3", @"Album W"),
            extendedRow(now - 730 * day, 200000, @"Song A", @"Artist 1", @"Album X"),
            extendedRow(now - 4 * day, 1800000, nil, nil, nil),
            extendedRow(now - 4 * day + 100, 10000, @"Song E", @"Artist 4", @"Album V"),
            @{@"ms_played": @50000, @"ts": NSNull.null},
        ];
        NSArray<SGPlay *> *ext = SGPlaysFromExport(json(extended));
        CHECK(ext.count == 6, "extended: 6 music plays kept of 9 rows (podcast, skip, no ts out): %lu", (unsigned long)ext.count);
        CHECK(ext.firstObject.end == now - 3 * day, "extended: ts read as UTC to the second");
        CHECK([ext.firstObject.album isEqualToString:@"Album X"] && [ext.firstObject.uri isEqualToString:@"spotify:track:Song A"],
              "extended: album and URI read");

        // Basic: the same two Song A plays 20 s later than the extended ts (minute stamps and drift), a play
        // only the basic file has, a 5 s skip and a podcast-shaped row.
        NSArray *basic = @[
            basicRow(now - 3 * day + 20, 200000, @"Song A", @"Artist 1"),
            basicRow(now - 3 * day + 300 + 20, 180000, @"Song A", @"Artist 1"),
            basicRow(now - 1 * day, 100000, @"Song F", @"Artist 2"),
            basicRow(now - 1 * day + 400, 5000, @"Song F", @"Artist 2"),
            @{@"endTime": stamp(now, NO), @"podcastName": @"Pod", @"episodeName": @"Ep", @"msPlayed": @900000},
        ];
        NSArray<SGPlay *> *bas = SGPlaysFromExport(json(basic));
        CHECK(bas.count == 3, "basic: 3 music plays kept of 5 rows: %lu", (unsigned long)bas.count);
        CHECK(bas.firstObject.end == now - 3 * day, "basic: endTime read as UTC, to the minute");
        CHECK(SGPlaysFromExport(json(@[@{@"spotify": @"settings"}])) == nil, "a JSON array that is not an export is refused");
        CHECK(SGPlaysFromExport(json(@{@"settings": @{}})) == nil, "a JSON object is refused");
        CHECK(SGPlaysFromExport([@"not json" dataUsingEncoding:NSUTF8StringEncoding]) == nil, "not JSON is refused");

        // Zips as the export arrives, stored and deflated, with a PDF and a __MACOSX twin beside the JSON.
        [json(extended) writeToFile:[exportDir stringByAppendingPathComponent:@"Streaming_History_Audio_2023.json"] atomically:YES];
        [json(basic) writeToFile:[exportDir stringByAppendingPathComponent:@"StreamingHistory_music_0.json"] atomically:YES];
        [@"readme" writeToFile:[exportDir stringByAppendingPathComponent:@"ReadMeFirst.pdf"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [@"junk" writeToFile:[exportDir stringByAppendingPathComponent:@"__MACOSX/._StreamingHistory_music_0.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSArray *names = @[@"Streaming_History_Audio_2023.json", @"StreamingHistory_music_0.json", @"ReadMeFirst.pdf", @"__MACOSX/._StreamingHistory_music_0.json"];
        for (NSNumber *stored in @[@YES, @NO]) {
            NSString *path = [dir stringByAppendingPathComponent:stored.boolValue ? @"stored.zip" : @"deflated.zip"];
            zip(exportDir, path, names, stored.boolValue);
            NSArray<NSData *> *files = SGJSONFilesInZip([NSData dataWithContentsOfFile:path]);
            NSUInteger plays = 0;
            for (NSData *file in files) plays += SGPlaysFromExport(file).count;
            CHECK(files.count == 2 && plays == 9, "%s zip: 2 JSON files, 9 plays: %lu files, %lu plays",
                  stored.boolValue ? "stored" : "deflated", (unsigned long)files.count, (unsigned long)plays);
        }
        CHECK(SGJSONFilesInZip(json(extended)).count == 0, "a file that is not a zip has no files in it");
        NSData *deflated = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"deflated.zip"]];
        CHECK(SGJSONFilesInZip([deflated subdataWithRange:NSMakeRange(0, deflated.length / 2)]).count == 0, "a cut-off zip reads as empty");
        for (NSNumber *declared in @[@1, @(65 * 1024 * 1024)]) {
            NSMutableData *forged = [deflated mutableCopy];
            uint8_t *bytes = forged.mutableBytes;
            for (NSUInteger i = 0; i + 46 <= forged.length; i++) {
                if (bytes[i] != 0x50 || bytes[i + 1] != 0x4b || bytes[i + 2] != 1 || bytes[i + 3] != 2) continue;
                uint32_t size = declared.unsignedIntValue;
                for (NSUInteger b = 0; b < 4; b++) bytes[i + 24 + b] = (uint8_t)(size >> (8 * b));
            }
            CHECK(SGJSONFilesInZip(forged).count == 0, "zip: understated/oversized expanded lengths rejected (%u)", declared.unsignedIntValue);
        }

        // The log: Song B recorded on the phone 30 s after the export's, then both files merged, twice.
        NSString *logPath = [dir stringByAppendingPathComponent:@"Vitrine/plays.tsv"];
        SGPlayLog *log = [[SGPlayLog alloc] initWithPath:logPath];
        SGPlay *recorded = play(now - 3 * day + 630, 61000, @"Song B", @"Artist 2", @"Album Y");
        recorded.uri = @"spotify:track:b";
        [log record:recorded];
        NSUInteger added = [log merge:ext];
        CHECK(added == 5, "merge extended: 5 added, the recorded Song B already there: %lu", (unsigned long)added);
        added = [log merge:bas];
        CHECK(added == 1, "merge basic: only Song F is new: %lu", (unsigned long)added);
        added = [log merge:ext] + [log merge:bas];
        CHECK(added == 0, "importing the same files again adds nothing: %lu", (unsigned long)added);
        CHECK([log merge:@[play(now, 40000, @"Tab\there", @"New\nline", @"")]] == 1, "a title with a tab and an artist with a newline merge");

        SGPlayLog *reread = [[SGPlayLog alloc] initWithPath:logPath];
        CHECK(reread.plays.count == 8, "the log reads back 8 plays: %lu", (unsigned long)reread.plays.count);
        SGPlay *last = reread.plays.lastObject;
        CHECK([last.title isEqualToString:@"Tab here"] && [last.artist isEqualToString:@"New line"], "tab and newline become spaces");
        CHECK([reread.plays.firstObject.uri isEqualToString:@"spotify:track:b"] && reread.plays.firstObject.ms == 61000, "the recorded play round-trips");

        // Periods from the fixed now. Week: Song A x2, Song B, Song F, Tab here. Month adds Song C, year
        // Song D, all time the old Song A.
        NSArray *plays = reread.plays;
        SGStats *week = SGStatsSince(plays, now - 7 * day, 10), *month = SGStatsSince(plays, now - 30 * day, 10);
        SGStats *year = SGStatsSince(plays, now - 365 * day, 10), *all = SGStatsSince(plays, 0, 10);
        CHECK(week.plays == 5 && month.plays == 6 && year.plays == 7 && all.plays == 8, "plays per period 5/6/7/8: %lu/%lu/%lu/%lu",
              (unsigned long)week.plays, (unsigned long)month.plays, (unsigned long)year.plays, (unsigned long)all.plays);
        CHECK(week.ms == 200000 + 180000 + 61000 + 100000 + 40000, "week: listening time adds up: %lld", week.ms);
        CHECK([week.tracks.firstObject.name isEqualToString:@"Song A"] && week.tracks.firstObject.plays == 2, "week: Song A tops the tracks with 2 plays");
        CHECK([week.artists[0].name isEqualToString:@"Artist 1"] && [week.artists[1].name isEqualToString:@"Artist 2"] && week.artists[1].plays == 2,
              "week: Artists 1 and 2 tie on 2 plays, and the one listened to longer leads");
        CHECK(all.tracks.firstObject.plays == 3 && [all.tracks.firstObject.name isEqualToString:@"Song A"], "all time: Song A x3");
        CHECK([all.artists.firstObject.name isEqualToString:@"Artist 1"] && all.artists.firstObject.plays == 4, "all time: Artist 1 x4");
        CHECK(all.albums.count == 4 && [all.albums.firstObject.name isEqualToString:@"Album X"], "all time: 4 albums (basic plays have none), Album X first");
        CHECK(SGStatsSince(plays, 0, 2).tracks.count == 2, "a top list is capped");

        CHECK(SGPlayCounts(30, 300) && !SGPlayCounts(29, 300) && SGPlayCounts(20, 40) && !SGPlayCounts(19, 40) && !SGPlayCounts(10, 0),
              "a play counts past 30 s or half the track");

        calendarChecks();
        localHistoryChecks(dir, reread.plays);

        // An export's size: 100k extended rows.
        NSMutableArray *big = [NSMutableArray arrayWithCapacity:100000];
        for (int i = 0; i < 100000; i++) {
            [big addObject:extendedRow(now - i * 200, 120000, [NSString stringWithFormat:@"Track %d", i % 3000],
                                       [NSString stringWithFormat:@"Artist %d", i % 400], [NSString stringWithFormat:@"Album %d", i % 900])];
        }
        NSData *bigData = json(big);
        NSString *bigPath = [dir stringByAppendingPathComponent:@"big.tsv"];
        NSDate *start = [NSDate date];
        NSArray *bigPlays = SGPlaysFromExport(bigData);
        double parse = since(start);
        SGPlayLog *bigLog = [[SGPlayLog alloc] initWithPath:bigPath];
        start = [NSDate date];
        NSUInteger bigAdded = [bigLog merge:bigPlays];
        double merge = since(start);
        start = [NSDate date];
        NSUInteger again = [bigLog merge:bigPlays];
        double remerge = since(start);
        start = [NSDate date];
        SGPlayLog *bigReread = [[SGPlayLog alloc] initWithPath:bigPath];
        NSUInteger readBack = bigReread.plays.count;
        double load = since(start);
        start = [NSDate date];
        SGStatsSince(bigReread.plays, 0, 10);
        double stats = since(start);
        start = [NSDate date];
        SGListeningStreaks *largeStreak = SGStreaks(bigReread.plays, [NSDate dateWithTimeIntervalSince1970:now], NSCalendar.currentCalendar);
        NSArray<SGStatEntry *> *largeHours = SGHourlyStats(bigReread.plays, 0, NSCalendar.currentCalendar);
        NSUInteger hourlyPlays = 0;
        for (SGStatEntry *hour in largeHours) hourlyPlays += hour.plays;
        double calendar = since(start);
        CHECK(bigAdded == 100000 && again == 0 && readBack == 100000, "100k rows: all added, none twice, all read back");
        CHECK(largeStreak.best > 200 && hourlyPlays == 100000, "100k rows: calendar aggregations retain every play");
        printf("      100k rows (%.1f MB JSON): parse %.0f ms, merge %.0f ms, merge again %.0f ms, load %.0f ms, add up %.0f ms\n",
               bigData.length / 1e6, parse, merge, remerge, load, stats);
        printf("      100k rows: streaks + hourly buckets %.0f ms\n", calendar);

        printf(failures ? "\n%d FAILED\n" : "\nall passed\n", failures);
        return failures ? 1 : 0;
    }
}
