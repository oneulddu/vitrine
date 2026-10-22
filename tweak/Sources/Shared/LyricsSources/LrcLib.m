// LRCLIB, the floor of the order. It is an open library with no key and no catalog to license, so
// it holds what the rest cannot: the tracks Apple's word by word program never reached, and the
// ones Musixmatch may show nobody. It mostly times lines and not words, which is the whole point of
// putting it last — the estimate inside a line is still a sweep, where Spotify's own lyrics only
// scroll. A record someone has timed by the word carries a Lyricsfile too (Lyricsfile.m), read first.
//
// Its /api/get wants the length to agree almost exactly and answers 404 otherwise, so a miss falls
// back to /api/search, which answers with whole recordings to pick the closest of. LRCLIB asks that
// clients say who they are, and the mod does.
#import "Core/SGCore.h"
#import "LyricsSources.h"

static NSString *const kGet = @"https://lrclib.net/api/get";
static NSString *const kSearch = @"https://lrclib.net/api/search";
// Line timing is only worth taking from a recording of about the same length as the one playing.
static const NSInteger kLengthSlack = 4;

static NSDictionary<NSString *, NSString *> *headers(void) {
    return @{@"User-Agent": @"Vitrine " @SG_VERSION};
}

// Bound transport before JSON allocation, and each sheet before ranking or LRC conversion.
static void getJSON(NSURL *url, void (^done)(id)) {
    SGLyricsSourceRequest(url, headers(), nil, ^(NSData *data, NSInteger status) {
        id reply = status == 200 && data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        done(reply);
    });
}

static BOOL boundedSheet(id text) {
    if (![text isKindOfClass:NSString.class]) return YES;
    if ([text length] > 256 * 1024 || [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 256 * 1024) return NO;
    __block NSUInteger lines = 0;
    [text enumerateSubstringsInRange:NSMakeRange(0, [text length])
                            options:NSStringEnumerationByLines | NSStringEnumerationSubstringNotRequired
                         usingBlock:^(NSString *line, NSRange range, NSRange enclosing, BOOL *stop) {
        if (++lines > 4000) *stop = YES;
    }];
    return lines <= 4000;
}

static BOOL boundedRecord(id record) {
    return [record isKindOfClass:NSDictionary.class] &&
        boundedSheet(record[@"syncedLyrics"]) && boundedSheet(record[@"plainLyrics"]);
}

// [00:34.30] Look — the timestamp in minutes, seconds and hundredths, or thousandths where a line
// carries three digits. A line may be stamped more than once when it is sung more than once, and
// the tags LRC opens with ([ar:…], [length:…]) are not timestamps, so they fall out on their own.
static NSArray<SGKaraokeLine *> *linesFromLRC(NSString *lrc) {
    static NSRegularExpression *stamp;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        stamp = [NSRegularExpression regularExpressionWithPattern:@"\\[(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]" options:0 error:nil];
    });
    NSMutableArray<NSDictionary *> *stamped = [NSMutableArray array];
    for (NSString *row in [lrc componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSArray<NSTextCheckingResult *> *found = [stamp matchesInString:row options:0 range:NSMakeRange(0, row.length)];
        // Only the stamps a line opens with are its own; one further in is part of the words.
        NSUInteger end = 0;
        NSMutableArray<NSNumber *> *at = [NSMutableArray array];
        for (NSTextCheckingResult *match in found) {
            if (match.range.location != end) break;
            end = NSMaxRange(match.range);
            NSInteger minutes = [row substringWithRange:[match rangeAtIndex:1]].integerValue;
            NSInteger seconds = [row substringWithRange:[match rangeAtIndex:2]].integerValue;
            NSInteger fraction = 0;
            NSRange part = [match rangeAtIndex:3];
            if (part.location != NSNotFound) {
                NSString *digits = [row substringWithRange:part];
                fraction = digits.integerValue * (digits.length == 1 ? 100 : digits.length == 2 ? 10 : 1);
            }
            [at addObject:@((minutes * 60 + seconds) * 1000 + fraction)];
        }
        if (!at.count) continue;
        NSString *text = [[row substringFromIndex:end] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        for (NSNumber *ms in at) [stamped addObject:@{@"ms": ms, @"text": text}];
    }
    if (!stamped.count) return nil;
    [stamped sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"ms"] compare:b[@"ms"]];
    }];
    // The empty rows stay in: they are the breaks, and each one is the end of the line before it.
    NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (NSDictionary *row in stamped) {
        [starts addObject:row[@"ms"]];
        [texts addObject:row[@"text"]];
    }
    return SGKaraokeEstimatedLines(starts, texts);
}

static SGLyricsResult *syncedResult(NSArray<SGKaraokeLine *> *lines) {
    if (!lines) return nil;
    SGLyricsResult *result = [SGLyricsResult new];
    result.synced = YES;
    result.karaokeLines = lines;
    NSArray<NSNumber *> *starts;
    NSArray<NSString *> *texts;
    SGLyricsPageLines(lines, &starts, &texts);
    result.starts = starts;
    result.texts = texts;
    return result;
}

SGLyricsResult *SGLyricsLRCResult(NSString *lrc) {
    return syncedResult([lrc isKindOfClass:NSString.class] ? linesFromLRC(lrc) : nil);
}

SGLyricsResult *SGLrcLibRecordResult(NSDictionary *record) {
    if (!boundedRecord(record)) return nil;
    SGLyricsResult *result;
    if ([record[@"instrumental"] isKindOfClass:NSNumber.class] && [record[@"instrumental"] boolValue]) {
        result = [SGLyricsResult new];
        result.instrumental = YES;
    } else {
        result = [record[@"hasWordSync"] isEqual:@YES] ? syncedResult(SGLyricsfileLines(record[@"lyricsfile"])) : nil;
        if (result) result.wordTimed = YES;
        else {
            if ([record[@"hasWordSync"] isEqual:@YES]) SGLog(@"lrclib: record %@ times words in a Lyricsfile this cannot read", record[@"id"]);
            result = SGLyricsLRCResult(record[@"syncedLyrics"]);
        }
        if (!result.karaokeLines.count) result = SGLyricsPlainResult(record[@"plainLyrics"], @"LRCLIB");
        if (!result.karaokeLines.count) return nil;
    }
    result.provider = @"LRCLIB";
    result.pageProvider = @"LRCLIB";
    return result;
}

void SGLrcLibGetID(NSNumber *recordID, void (^done)(SGLyricsResult *result)) {
    NSString *identifier = SGLyricsDecimalID(recordID);
    if (!identifier.length) { done(nil); return; }
    NSURL *url = [NSURL URLWithString:[kGet stringByAppendingFormat:@"/%@", identifier]];
    getJSON(url, ^(id record) { done(SGLrcLibRecordResult(record)); });
}

// Search is for a person choosing a recording: keep different lengths, and show the closest first
// within each timing kind. A malformed record has nothing useful to choose and is left out.
static NSArray<NSDictionary *> *searchRecords(id reply, NSInteger seconds) {
    NSMutableArray<NSDictionary *> *records = [NSMutableArray array];
    NSUInteger read = 0;
    for (id raw in [reply isKindOfClass:NSArray.class] ? reply : @[]) {
        if (read++ >= 100) break;
        if (!boundedRecord(raw)) continue;
        id identifier = raw[@"id"];
        if (![identifier isKindOfClass:NSNumber.class] || !SGLyricsDecimalID(identifier).length || [identifier longLongValue] <= 0) continue;
        double duration = 0;
        if (!SGLyricsNumber(raw[@"duration"], &duration)) duration = 0;
        if (!isfinite(duration) || duration < 0 || duration > 86400) duration = 0;
        BOOL synced = [raw[@"syncedLyrics"] isKindOfClass:NSString.class] && [raw[@"syncedLyrics"] length];
        BOOL instrumental = [raw[@"instrumental"] isKindOfClass:NSNumber.class] && [raw[@"instrumental"] boolValue];
        [records addObject:@{@"id": identifier, @"title": SGLyricsString(raw[@"trackName"], 4096) ?: @"",
                             @"artist": SGLyricsString(raw[@"artistName"], 4096) ?: @"",
                             @"album": SGLyricsString(raw[@"albumName"], 4096) ?: @"", @"seconds": @(duration),
                             @"synced": @(synced), @"instrumental": @(instrumental), @"record": raw}];
    }
    [records sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        if ([a[@"synced"] boolValue] != [b[@"synced"] boolValue]) return [a[@"synced"] boolValue] ? NSOrderedAscending : NSOrderedDescending;
        if (seconds <= 0) return NSOrderedSame;
        double off = fabs([a[@"seconds"] doubleValue] - seconds), wasOff = fabs([b[@"seconds"] doubleValue] - seconds);
        return off < wasOff ? NSOrderedAscending : off > wasOff ? NSOrderedDescending : NSOrderedSame;
    }];
    return records.count > 20 ? [records subarrayWithRange:NSMakeRange(0, 20)] : [records copy];
}

void SGLrcLibSearch(NSString *title, NSString *artist, NSInteger seconds, void (^done)(NSArray<NSDictionary *> *records)) {
    void (^search)(void) = ^{
        if (!title.length && !artist.length) { done(@[]); return; }
        NSMutableDictionary *query = [NSMutableDictionary dictionary];
        if (title.length) query[@"track_name"] = title;
        if (artist.length) query[@"artist_name"] = artist;
        getJSON(SGLyricsURL(kSearch, query), ^(id reply) { done(searchRecords(reply, seconds)); });
    };
    if (NSThread.isMainThread) search();
    else dispatch_async(dispatch_get_main_queue(), search);
}

// How good a recording is for the track: words timed beat lines timed, which beat untimed, then the
// closest length. With no length to go on, the fullest sheet wins — the search will happily rank a
// seventeen second stub of a song above the song, and a stub is the one thing a length would have
// caught.
static BOOL betterRecord(NSDictionary *record, NSDictionary *best, NSInteger seconds) {
    if (!best) return YES;
    BOOL worded = [record[@"hasWordSync"] isEqual:@YES], wasWorded = [best[@"hasWordSync"] isEqual:@YES];
    if (worded != wasWorded) return worded;
    BOOL synced = [record[@"syncedLyrics"] isKindOfClass:NSString.class] && [record[@"syncedLyrics"] length];
    BOOL wasSynced = [best[@"syncedLyrics"] isKindOfClass:NSString.class] && [best[@"syncedLyrics"] length];
    if (synced != wasSynced) return synced;
    if (seconds > 0) {
        NSInteger off = labs((NSInteger)[record[@"duration"] doubleValue] - seconds);
        NSInteger wasOff = labs((NSInteger)[best[@"duration"] doubleValue] - seconds);
        return off < wasOff;
    }
    NSString *text = record[@"syncedLyrics"] ?: record[@"plainLyrics"] ?: @"";
    NSString *wasText = best[@"syncedLyrics"] ?: best[@"plainLyrics"] ?: @"";
    return [text isKindOfClass:NSString.class] && (![wasText isKindOfClass:NSString.class] || text.length > wasText.length);
}

static NSDictionary *bestOf(id found, NSInteger seconds) {
    NSDictionary *best = nil;
    NSUInteger read = 0;
    for (NSDictionary *record in [found isKindOfClass:NSArray.class] ? found : @[]) {
        if (read++ >= 100) break;
        if (!boundedRecord(record)) continue;
        NSInteger length = (NSInteger)[record[@"duration"] doubleValue];
        if (seconds > 0 && length > 0 && labs(length - seconds) > kLengthSlack) continue;
        if (betterRecord(record, best, seconds)) best = record;
    }
    return best;
}

SGLyricsAsk SGLrcLibAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    if (!query.title.length || !query.artist.length) {
        SGLog(@"lrclib: nothing to search with for %@", query.trackID);
        done(nil);
        return;
    }
    NSMutableDictionary<NSString *, NSString *> *search = [NSMutableDictionary dictionaryWithDictionary:@{
        @"track_name": query.title,
        @"artist_name": query.artist,
    }];
    if (query.album.length) search[@"album_name"] = query.album;

    void (^bySearch)(void) = ^{
        getJSON(SGLyricsURL(kSearch, search), ^(id found) {
            NSDictionary *record = bestOf(found, query.seconds);
            SGLyricsResult *result = SGLrcLibRecordResult(record);
            SGLog(@"lrclib: search for %@ by %@ gave %@", query.title, query.artist,
                  !result ? @"nothing" : result.instrumental ? @"an instrumental"
                  : result.synced ? [NSString stringWithFormat:@"%lu %@ lines", (unsigned long)result.karaokeLines.count, result.wordTimed ? @"word timed" : @"timed"]
                  : [NSString stringWithFormat:@"%lu untimed lines", (unsigned long)result.texts.count]);
            done(result);
        });
    };

    // With no length to match on, the exact lookup would be a guess; the search ranks by itself.
    if (query.seconds <= 0) {
        bySearch();
        return;
    }
    NSMutableDictionary<NSString *, NSString *> *exact = [search mutableCopy];
    exact[@"duration"] = @(query.seconds).stringValue;
    getJSON(SGLyricsURL(kGet, exact), ^(id record) {
        SGLyricsResult *result = SGLrcLibRecordResult(record);
        if (!result) {
            bySearch();
            return;
        }
        SGLog(@"lrclib: %@ by %@ matched exactly, %@", query.title, query.artist,
              result.instrumental ? @"instrumental" : result.wordTimed ? @"word timed" : result.synced ? @"timed" : @"untimed");
        done(result);
    });
};
