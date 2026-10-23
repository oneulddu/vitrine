// SGPlayLog.h says what the log holds and why it is a text file.
#include <stdio.h>
#include <time.h>
#include <errno.h>
#include <compression.h>
#include <dlfcn.h>
#import "Core/SGLocalize.h"
#import "SGPlayLog.h"

NSNotificationName const SGPlayLogDidChangeNotification = @"SGPlayLogDidChange";

@implementation SGPlay
@end

@implementation SGStatEntry
@end

@implementation SGStats
@end
@implementation SGListeningStreaks
@end
@implementation SGStatBucket
@end
@implementation SGHistoryImport
@end

static const NSUInteger SGHistoryFileLimit = 64 * 1024 * 1024;
static const NSUInteger SGHistoryTotalLimit = 256 * 1024 * 1024;
static const NSUInteger SGHistoryPlayLimit = 1000000;

static BOOL historyInteger(id value, int64_t *out) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NO;
    const char *text = [value stringValue].UTF8String;
    char *tail;
    errno = 0;
    long long number = strtoll(text, &tail, 10);
    if (errno || tail == text || *tail) return NO;
    *out = number;
    return YES;
}

static NSArray<SGPlay *> *localHistory(NSDictionary *root) {
    int64_t version;
    if (![root[@"format"] isEqual:@"vitrine.listening-history"] ||
        !historyInteger(root[@"version"], &version) || version != 1 ||
        ![root[@"plays"] isKindOfClass:NSArray.class] || [root[@"plays"] count] > SGHistoryPlayLimit) return nil;
    NSMutableArray *plays = [NSMutableArray array];
    for (id row in root[@"plays"]) {
        int64_t end, ms;
        if (![row isKindOfClass:NSDictionary.class] || !historyInteger(row[@"end"], &end) ||
            !historyInteger(row[@"ms"], &ms) || ms < 0 || end < -62135596800LL || end > 253402300799LL) return nil;
        for (NSString *key in @[@"uri", @"title", @"artist", @"album"])
            if (![row[key] isKindOfClass:NSString.class]) return nil;
        SGPlay *p = [SGPlay new];
        p.end = end; p.ms = ms; p.uri = row[@"uri"]; p.title = row[@"title"];
        p.artist = row[@"artist"]; p.album = row[@"album"]; p.exactImport = YES;
        [plays addObject:p];
    }
    return plays;
}

NSData *SGHistoryJSON(NSArray<SGPlay *> *plays, NSError **error) {
    if (plays.count > SGHistoryPlayLimit) {
        if (error) *error = [NSError errorWithDomain:@"VitrineHistory" code:1 userInfo:@{NSLocalizedDescriptionKey:
            SGL(@"settings.stats.error.export_play_limit", @"History exceeds the one-million-play export limit. Your history on this phone is unchanged.")}];
        return nil;
    }
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:plays.count];
    for (SGPlay *p in plays) [rows addObject:@{@"end": @(p.end), @"ms": @(p.ms), @"uri": p.uri ?: @"",
        @"title": p.title ?: @"", @"artist": p.artist ?: @"", @"album": p.album ?: @""}];
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"format": @"vitrine.listening-history", @"version": @1, @"plays": rows}
                                                 options:0 error:error];
    if (data.length > SGHistoryFileLimit) {
        if (error) *error = [NSError errorWithDomain:@"VitrineHistory" code:2 userInfo:@{NSLocalizedDescriptionKey:
            SGL(@"settings.stats.error.export_size_limit", @"History exceeds the 64 MiB JSON export limit. Your history on this phone is unchanged.")}];
        return nil;
    }
    return data;
}

BOOL SGPlayCounts(double listened, double duration) {
    return listened * 1000 >= SGPlayMinimumMs || (duration > 0 && listened >= duration / 2);
}

static NSString *stringIn(id value) {
    return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

// Both shapes are UTC. sscanf and timegm rather than NSDateFormatter: an extended export runs to 100k
// rows and more, and the formatter costs microseconds a row.
static int64_t timeIn(NSString *text, BOOL seconds) {
    struct tm tm = {0};
    const char *c = text.UTF8String;
    int n = seconds ? sscanf(c, "%d-%d-%dT%d:%d:%d", &tm.tm_year, &tm.tm_mon, &tm.tm_mday, &tm.tm_hour, &tm.tm_min, &tm.tm_sec)
                    : sscanf(c, "%d-%d-%d %d:%d", &tm.tm_year, &tm.tm_mon, &tm.tm_mday, &tm.tm_hour, &tm.tm_min);
    if (n < (seconds ? 6 : 5)) return 0;
    tm.tm_year -= 1900;
    tm.tm_mon -= 1;
    return (int64_t)timegm(&tm);
}

// ponytail: the export has no track lengths, so an imported play counts from 30 s only; a full play of
// a track under 30 s is left out. The extended rows' reason_end could tell a finished track apart.
static SGPlay *playFrom(NSDictionary *row) {
    NSString *title, *artist, *album = @"", *uri = @"";
    int64_t end, ms;
    if (row[@"ts"]) {
        title = stringIn(row[@"master_metadata_track_name"]);
        artist = stringIn(row[@"master_metadata_album_artist_name"]);
        album = stringIn(row[@"master_metadata_album_album_name"]) ?: @"";
        uri = stringIn(row[@"spotify_track_uri"]) ?: @"";
        end = stringIn(row[@"ts"]) ? timeIn(row[@"ts"], YES) : 0;
        ms = [row[@"ms_played"] isKindOfClass:NSNumber.class] ? [row[@"ms_played"] longLongValue] : 0;
    } else {
        title = stringIn(row[@"trackName"]);
        artist = stringIn(row[@"artistName"]);
        end = stringIn(row[@"endTime"]) ? timeIn(row[@"endTime"], NO) : 0;
        ms = [row[@"msPlayed"] isKindOfClass:NSNumber.class] ? [row[@"msPlayed"] longLongValue] : 0;
    }
    if (!title || !artist || end <= 0 || ms < SGPlayMinimumMs) return nil;
    SGPlay *play = [SGPlay new];
    play.end = end;
    play.ms = ms;
    play.uri = uri;
    play.title = title;
    play.artist = artist;
    play.album = album;
    return play;
}

NSArray<SGPlay *> *SGPlaysFromExport(NSData *json) {
    if (json.length > SGHistoryFileLimit) return nil;
    id rows = json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
    if ([rows isKindOfClass:NSDictionary.class]) return localHistory(rows);
    if (![rows isKindOfClass:NSArray.class]) return nil;
    if ([rows count] > SGHistoryPlayLimit) return nil;
    NSMutableArray<SGPlay *> *plays = [NSMutableArray array];
    BOOL known = NO;
    for (NSDictionary *row in rows) {
        if (![row isKindOfClass:NSDictionary.class]) continue;
        // Podcast files of either shape have their own keys, and the extended one's music rows have
        // ts and ms_played, so the keys say what a file is whatever it was renamed to.
        if (!(row[@"ts"] && row[@"ms_played"]) && !(row[@"endTime"] && row[@"msPlayed"])) continue;
        known = YES;
        SGPlay *play = playFrom(row);
        if (play) [plays addObject:play];
    }
    return known || [rows count] == 0 ? plays : nil;
}

#pragma mark - zip

static uint32_t le(const uint8_t *p, int bytes) {
    uint32_t v = 0;
    for (int i = bytes - 1; i >= 0; i--) v = v << 8 | p[i];
    return v;
}

// A declared ZIP size is not trustworthy. Give the system decoder a fixed output buffer, with one
// extra byte to detect an understated size; NSData's unbounded decompressor can allocate far more.
// Resolve from the system library so Foundation-only harnesses need no extra linker flags.
static NSData *inflateHistory(const uint8_t *bytes, size_t packed, size_t length) {
    static size_t (*decode)(uint8_t *, size_t, const uint8_t *, size_t, void *, compression_algorithm);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *library = dlopen("/usr/lib/libcompression.dylib", RTLD_LOCAL | RTLD_LAZY);
        if (library) decode = dlsym(library, "compression_decode_buffer");
    });
    if (!decode) return nil;
    void *out = malloc(length + 1);
    if (!out) return nil;
    size_t written = decode(out, length + 1, bytes, packed, NULL, COMPRESSION_ZLIB);
    if (written != length) { free(out); return nil; }
    return [NSData dataWithBytesNoCopy:out length:length freeWhenDone:YES];
}

// The central directory names each entry and where it starts; stored and raw DEFLATE entries are read.
// ponytail: no ZIP64, so a zip over 4 GB or 65535 entries reads as empty; an export is far smaller.
static NSArray<NSData *> *historyJSONFilesInZip(NSData *zip, NSUInteger *skipped, NSUInteger expandedLimit,
                                                NSUInteger *expandedConsumed) {
    NSMutableArray<NSData *> *files = [NSMutableArray array];
    const uint8_t *b = zip.bytes;
    size_t size = zip.length;
    expandedLimit = MIN(expandedLimit, SGHistoryTotalLimit);
    if (size < 22 || size > SGHistoryTotalLimit || !expandedLimit) return files;
    NSUInteger expanded = 0, jsonCount = 0;
    size_t eocd = SIZE_MAX;
    size_t floor = size > 22 + 0xFFFF ? size - 22 - 0xFFFF : 0;
    for (size_t i = size - 22; ; i--) {
        if (le(b + i, 4) == 0x06054b50) { eocd = i; break; }
        if (i == floor) break;
    }
    if (eocd == SIZE_MAX) return files;
    uint32_t count = le(b + eocd + 10, 2);
    size_t at = le(b + eocd + 16, 4);
    for (uint32_t n = 0; n < count; n++) {
        if (n >= 10000) { if (skipped) (*skipped)++; break; }
        if (at + 46 > size || le(b + at, 4) != 0x02014b50) break;
        uint32_t method = le(b + at + 10, 2), packed = le(b + at + 20, 4), length = le(b + at + 24, 4);
        uint32_t nameLength = le(b + at + 28, 2), extra = le(b + at + 30, 2), comment = le(b + at + 32, 2);
        size_t local = le(b + at + 42, 4);
        if (at + 46 + nameLength > size) break;
        NSString *name = [[NSString alloc] initWithBytes:b + at + 46 length:nameLength encoding:NSUTF8StringEncoding];
        at += 46 + nameLength + extra + comment;

        BOOL json = [name.lowercaseString hasSuffix:@".json"];
        for (NSString *component in name.pathComponents)
            if ([component hasPrefix:@"."] || [component isEqualToString:@"__MACOSX"]) json = NO;
        if (!json) continue;
        if (++jsonCount > 1000) { if (skipped) (*skipped)++; continue; }
        if (local + 30 > size || le(b + local, 4) != 0x04034b50) { if (skipped) (*skipped)++; continue; }
        size_t data = local + 30 + le(b + local + 26, 2) + le(b + local + 28, 2);
        if (data + packed > size || length > SGHistoryFileLimit || length > expandedLimit - expanded || files.count >= 1000) {
            if (skipped) (*skipped)++;
            continue;
        }
        expanded += length; // Failed decoding consumes the budget too.
        if (method == 0 && packed == length) {
            [files addObject:[zip subdataWithRange:NSMakeRange(data, packed)]];
        } else if (method == 8 && length) {
            NSData *out = inflateHistory(b + data, packed, length);
            if (out.length == length) [files addObject:out];
            else if (skipped) (*skipped)++;
        } else if (skipped) (*skipped)++;
    }
    if (expandedConsumed) *expandedConsumed = expanded;
    return files;
}

NSArray<NSData *> *SGJSONFilesInZip(NSData *zip) { return historyJSONFilesInZip(zip, NULL, SGHistoryTotalLimit, NULL); }

#pragma mark - selected files and folders

SGHistoryImport *SGReadHistoryURLs(NSArray<NSURL *> *urls) {
    SGHistoryImport *result = [SGHistoryImport new];
    NSMutableArray *plays = [NSMutableArray array];
    __block NSUInteger visited = 0, files = 0, inputBytes = 0, jsonBytes = 0;
    NSArray *keys = @[NSURLIsDirectoryKey, NSURLIsRegularFileKey, NSURLIsSymbolicLinkKey, NSURLIsHiddenKey,
                      NSURLIsPackageKey, NSURLFileSizeKey];
    void (^readFile)(NSURL *) = ^(NSURL *url) {
        NSString *ext = url.pathExtension.lowercaseString;
        if (![@[@"json", @"zip"] containsObject:ext]) return;
        if (++files > 1000) { result.skipped++; return; }
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        NSError *error;
        [coordinator coordinateReadingItemAtURL:url options:NSFileCoordinatorReadingWithoutChanges error:&error byAccessor:^(NSURL *reading) {
            NSDictionary *values = [reading resourceValuesForKeys:keys error:nil];
            NSUInteger size = [values[NSURLFileSizeKey] unsignedIntegerValue];
            NSUInteger limit = [ext isEqualToString:@"zip"] ? SGHistoryTotalLimit : SGHistoryFileLimit;
            if (![values[NSURLIsRegularFileKey] boolValue] || [values[NSURLIsSymbolicLinkKey] boolValue] ||
                !size || size > limit || size > SGHistoryTotalLimit - inputBytes) { result.skipped++; return; }
            inputBytes += size;
            // Read at most the budget even if a provider changes the file after the size check.
            NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:reading error:nil];
            NSData *data = [handle readDataUpToLength:size + 1 error:nil];
            [handle closeAndReturnError:nil];
            if (!data || data.length > size) { result.skipped++; return; }
            NSUInteger zipSkipped = 0, zipExpanded = 0;
            NSUInteger remaining = SGHistoryTotalLimit - jsonBytes;
            BOOL zipped = [ext isEqualToString:@"zip"];
            NSArray *jsons = zipped ? historyJSONFilesInZip(data, &zipSkipped, remaining, &zipExpanded) : @[data];
            if (zipped) jsonBytes += zipExpanded; // Failed entries consume the shared allocation/decode budget too.
            result.skipped += zipSkipped;
            if (!jsons.count) result.skipped++;
            for (NSData *json in jsons) {
              @autoreleasepool {
                if (result.files >= 1000) { result.skipped++; break; }
                if (!zipped) {
                    if (json.length > SGHistoryTotalLimit - jsonBytes) { result.skipped++; continue; }
                    jsonBytes += json.length;
                }
                NSArray *found = SGPlaysFromExport(json);
                if (!found || found.count > SGHistoryPlayLimit - plays.count) { result.skipped++; continue; }
                result.files++;
                [plays addObjectsFromArray:found];
              }
            }
        }];
        if (error) result.skipped++;
    };
    for (NSURL *url in urls) {
        if (++visited > 10000) { result.skipped++; break; }
        if (!url.isFileURL) { result.skipped++; continue; }
        BOOL scoped = [url startAccessingSecurityScopedResource];
        @try {
            NSDictionary *values = [url resourceValuesForKeys:keys error:nil];
            if (!values || [values[NSURLIsSymbolicLinkKey] boolValue] || [values[NSURLIsHiddenKey] boolValue] ||
                [values[NSURLIsPackageKey] boolValue]) { result.skipped++; continue; }
            if (![values[NSURLIsDirectoryKey] boolValue]) { readFile(url); continue; }
            NSString *root = [url.URLByResolvingSymlinksInPath.path stringByAppendingString:@"/"];
            NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtURL:url includingPropertiesForKeys:keys
                options:NSDirectoryEnumerationSkipsHiddenFiles | NSDirectoryEnumerationSkipsPackageDescendants
                errorHandler:^BOOL(NSURL *failed, NSError *error) { result.skipped++; return YES; }];
            for (NSURL *child in enumerator) {
                if (++visited > 10000) { result.skipped++; break; }
                NSDictionary *v = [child resourceValuesForKeys:keys error:nil];
                if (!v || [v[NSURLIsSymbolicLinkKey] boolValue] || [v[NSURLIsPackageKey] boolValue] ||
                    [child.lastPathComponent isEqualToString:@"__MACOSX"] ||
                    ![child.URLByResolvingSymlinksInPath.path hasPrefix:root] || enumerator.level > 8) {
                    [enumerator skipDescendants]; result.skipped++; continue;
                }
                if (![v[NSURLIsDirectoryKey] boolValue] && [child.pathExtension.lowercaseString isEqualToString:@"json"]) readFile(child);
            }
        } @finally {
            if (scoped) [url stopAccessingSecurityScopedResource];
        }
    }
    result.plays = plays;
    return result;
}

#pragma mark - the log

static NSString *field(NSString *text) {
    if (!text) return @"";
    NSArray *parts = [text componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\t\r\n"]];
    return [parts componentsJoinedByString:@" "];
}

static NSString *lineOf(SGPlay *play) {
    return [NSString stringWithFormat:@"%lld\t%lld\t%@\t%@\t%@\t%@\n", play.end, play.ms, field(play.uri), field(play.title),
            field(play.artist), field(play.album)];
}

static NSString *keyOf(SGPlay *play) {
    return [NSString stringWithFormat:@"%@\x1f%@", play.title.lowercaseString, play.artist.lowercaseString];
}

static NSString *exactKeyOf(SGPlay *play) {
    // This is exactly the persisted representation, including field normalization, and NSString's
    // content hash keeps million-row imports linear instead of making equal-length tuple arrays collide.
    return lineOf(play);
}

static NSMutableArray<SGPlay *> *playsFromTSV(NSString *text) {
    NSMutableArray *plays = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSArray<NSString *> *f = [line componentsSeparatedByString:@"\t"];
        if (f.count < 6) continue;
        SGPlay *play = [SGPlay new];
        play.end = f[0].longLongValue; play.ms = f[1].longLongValue;
        play.uri = f[2]; play.title = f[3]; play.artist = f[4]; play.album = f[5];
        [plays addObject:play];
    }
    return plays;
}

@implementation SGPlayLog {
    NSString *_path;
    NSMutableArray<SGPlay *> *_plays;
    NSMutableArray<SGPlay *> *_duringLoad;
    NSMutableArray<void (^)(void)> *_loadCompletions;
    NSError *_loadError;
}

- (instancetype)initWithPath:(NSString *)path {
    if ((self = [super init])) _path = [path copy];
    return self;
}

- (NSArray<SGPlay *> *)plays {
    if (_plays) return _plays;
    NSString *text = [NSString stringWithContentsOfFile:_path encoding:NSUTF8StringEncoding error:nil];
    _plays = playsFromTSV(text);
    return _plays;
}

- (NSError *)loadError { return _loadError; }

- (void)loadWithCompletion:(void (^)(void))completion {
    NSAssert(NSThread.isMainThread, @"SGPlayLog belongs to main");
    if (_plays) { completion(); return; }
    if (_loadCompletions) { [_loadCompletions addObject:[completion copy]]; return; }
    _loadCompletions = [NSMutableArray arrayWithObject:[completion copy]];
    _duringLoad = [NSMutableArray array];
    // Capture the boundary before a recorder can append. Only the file handle crosses threads.
    NSError *openError;
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:[NSURL fileURLWithPath:_path] error:&openError];
    if ([openError.domain isEqual:NSCocoaErrorDomain] && openError.code == NSFileReadNoSuchFileError) openError = nil;
    unsigned long long length = 0;
    [handle seekToEndReturningOffset:&length error:&openError];
    [handle seekToOffset:0 error:&openError];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *readError = openError;
        NSData *data = [handle readDataUpToLength:(NSUInteger)length error:&readError];
        [handle closeAndReturnError:nil];
        NSString *text = [[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding];
        if (!readError && (!text || data.length < length)) readError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:nil];
        NSMutableArray *loaded = playsFromTSV(text);
        dispatch_async(dispatch_get_main_queue(), ^{
            // A synchronous reader, merge or erase meanwhile is authoritative.
            if (!self->_plays) {
                self->_loadError = readError;
                if (!readError) {
                    [loaded addObjectsFromArray:self->_duringLoad];
                    self->_plays = loaded;
                }
            }
            NSArray *callbacks = self->_loadCompletions;
            self->_loadCompletions = nil;
            self->_duringLoad = nil;
            for (void (^callback)(void) in callbacks) callback();
        });
    });
}

- (void)append:(NSArray<SGPlay *> *)plays {
    if (!plays.count) return;
    [NSFileManager.defaultManager createDirectoryAtPath:_path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableString *text = [NSMutableString string];
    for (SGPlay *play in plays) [text appendString:lineOf(play)];
    FILE *file = fopen(_path.fileSystemRepresentation, "a");
    if (!file) return;
    fputs(text.UTF8String, file);
    fclose(file);
}

// Not loaded for it: a play ending should not read the whole log on the main thread.
- (void)record:(SGPlay *)play {
    [_plays addObject:play];
    if (!_plays) [_duringLoad addObject:play];
    [self append:@[play]];
    [NSNotificationCenter.defaultCenter postNotificationName:SGPlayLogDidChangeNotification object:self];
}

- (NSUInteger)merge:(NSArray<SGPlay *> *)incoming {
    BOOL needsExact = [incoming indexOfObjectPassingTest:^BOOL(SGPlay *play, NSUInteger index, BOOL *stop) {
        return play.exactImport;
    }] != NSNotFound;
    NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *ends = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *exact = needsExact ? [NSMutableSet set] : nil;
    for (SGPlay *play in self.plays) {
        NSString *key = keyOf(play);
        if (!ends[key]) ends[key] = [NSMutableArray array];
        [ends[key] addObject:@(play.end)];
        if (needsExact) [exact addObject:exactKeyOf(play)];
    }
    NSMutableArray<SGPlay *> *added = [NSMutableArray array];
    for (SGPlay *play in incoming) {
        NSString *key = keyOf(play);
        NSString *exactKey = needsExact ? exactKeyOf(play) : nil;
        BOOL have = play.exactImport && [exact containsObject:exactKey];
        if (!play.exactImport) {
            for (NSNumber *end in ends[key]) {
                if (llabs(end.longLongValue - play.end) <= 90) { have = YES; break; }
            }
        }
        if (have) continue;
        if (!ends[key]) ends[key] = [NSMutableArray array];
        [ends[key] addObject:@(play.end)];
        if (needsExact) [exact addObject:exactKey];
        [added addObject:play];
    }
    [_plays addObjectsFromArray:added];
    [self append:added];
    if (added.count) [NSNotificationCenter.defaultCenter postNotificationName:SGPlayLogDidChangeNotification object:self];
    return added.count;
}

- (void)erase {
    [NSFileManager.defaultManager removeItemAtPath:_path error:nil];
    _plays = [NSMutableArray array];
    _loadError = nil;
    [NSNotificationCenter.defaultCenter postNotificationName:SGPlayLogDidChangeNotification object:self];
}

@end

#pragma mark - stats

static NSArray<SGStatEntry *> *topOf(NSDictionary<NSString *, SGStatEntry *> *entries, NSUInteger top) {
    NSArray<SGStatEntry *> *sorted = [entries.allValues sortedArrayUsingComparator:^NSComparisonResult(SGStatEntry *a, SGStatEntry *b) {
        if (a.plays != b.plays) return a.plays > b.plays ? NSOrderedAscending : NSOrderedDescending;
        if (a.ms != b.ms) return a.ms > b.ms ? NSOrderedAscending : NSOrderedDescending;
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    return [sorted subarrayWithRange:NSMakeRange(0, MIN(top, sorted.count))];
}

static void count(NSMutableDictionary<NSString *, SGStatEntry *> *entries, NSString *key, NSString *name, NSString *detail, SGPlay *play) {
    SGStatEntry *entry = entries[key];
    if (!entry) {
        entry = [SGStatEntry new];
        entry.name = name;
        entry.detail = detail;
        entries[key] = entry;
    }
    entry.plays++;
    entry.ms += play.ms;
}

// Tracks go by title and artist rather than URI: the basic export has no URIs, and a track's URI can
// differ between its single and its album.
SGStats *SGStatsSince(NSArray<SGPlay *> *plays, int64_t since, NSUInteger top) {
    return SGStatsBetween(plays, since, INT64_MAX, top);
}

SGStats *SGStatsBetween(NSArray<SGPlay *> *plays, int64_t start, int64_t end, NSUInteger top) {
    NSMutableDictionary<NSString *, SGStatEntry *> *tracks = [NSMutableDictionary dictionary], *artists = [NSMutableDictionary dictionary],
                                                   *albums = [NSMutableDictionary dictionary];
    SGStats *stats = [SGStats new];
    for (SGPlay *play in plays) {
        if (play.end < start || (end != INT64_MAX && play.end >= end)) continue;
        stats.plays++;
        stats.ms += play.ms;
        NSString *artist = play.artist.lowercaseString;
        count(tracks, keyOf(play), play.title, play.artist, play);
        count(artists, artist, play.artist, nil, play);
        if (play.album.length) count(albums, [NSString stringWithFormat:@"%@\x1f%@", play.album.lowercaseString, artist], play.album, play.artist, play);
    }
    stats.tracks = topOf(tracks, top);
    stats.artists = topOf(artists, top);
    stats.albums = topOf(albums, top);
    return stats;
}

SGListeningStreaks *SGStreaks(NSArray<SGPlay *> *plays, NSDate *now, NSCalendar *calendar) {
    NSCalendar *cal = [calendar copy];
    NSDate *today = [cal startOfDayForDate:now];
    NSMutableSet<NSDate *> *days = [NSMutableSet set];
    for (SGPlay *play in plays) {
        // NSDate/Calendar cannot represent arbitrary int64 timestamps from a damaged legacy log.
        if (play.end < -62135596800LL || play.end > 253402300799LL) continue;
        NSDate *day = [cal startOfDayForDate:[NSDate dateWithTimeIntervalSince1970:play.end]];
        if (day && [day compare:today] != NSOrderedDescending) [days addObject:day];
    }
    SGListeningStreaks *result = [SGListeningStreaks new];
    NSUInteger run = 0;
    NSDate *previous, *runStart;
    for (NSDate *day in [days.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        NSDate *next = previous ? [cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:previous options:0] : nil;
        if (next) next = [cal startOfDayForDate:next]; // Some zones skip midnight at DST start.
        run = [next isEqualToDate:day] ? run + 1 : 1;
        if (run == 1) runStart = day;
        if (run >= result.best) {
            result.best = run;
            result.bestStart = runStart;
            result.bestEnd = day;
        }
        previous = day;
    }
    NSDate *last = [days containsObject:today] ? today : [cal dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:today options:0];
    if (last) last = [cal startOfDayForDate:last];
    while (last && [days containsObject:last]) {
        if (!result.current) result.currentEnd = last;
        result.currentStart = last;
        result.current++;
        last = [cal dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:last options:0];
        if (last) last = [cal startOfDayForDate:last];
    }
    return result;
}

NSArray<SGStatEntry *> *SGHourlyStats(NSArray<SGPlay *> *plays, int64_t since, NSCalendar *calendar) {
    return SGHourlyStatsBetween(plays, since, INT64_MAX, calendar);
}

NSArray<SGStatEntry *> *SGHourlyStatsBetween(NSArray<SGPlay *> *plays, int64_t start, int64_t end, NSCalendar *calendar) {
    NSCalendar *cal = [calendar copy];
    NSMutableArray<SGStatEntry *> *hours = [NSMutableArray arrayWithCapacity:24];
    for (NSUInteger i = 0; i < 24; i++) [hours addObject:[SGStatEntry new]];
    for (SGPlay *play in plays) {
        if (play.end < start || play.end >= end || play.end < -62135596800LL || play.end > 253402300799LL) continue;
        NSInteger hour = [cal component:NSCalendarUnitHour fromDate:[NSDate dateWithTimeIntervalSince1970:play.end]];
        if (hour < 0 || hour > 23) continue;
        hours[hour].plays++;
        hours[hour].ms += play.ms;
    }
    return hours;
}

#pragma mark - calendar periods

static NSCalendarUnit periodUnit(SGStatsPeriod period) {
    return period == SGStatsPeriodYear ? NSCalendarUnitYear : period == SGStatsPeriodMonth ? NSCalendarUnitMonth : NSCalendarUnitWeekOfYear;
}

static int64_t unixSeconds(NSDate *date) {
    return (int64_t)floor(date.timeIntervalSince1970);
}

// The unit holding `date`, as [its start, the next one's start). The next start is looked up from a date one
// unit past the middle of this one, so neither a DST hour, a skipped midnight nor a short month can land
// it in the wrong unit, and the unit's length is the calendar's rather than a fixed count of seconds.
static NSDateInterval *unitInterval(NSCalendar *cal, NSCalendarUnit unit, NSDate *date) {
    NSDate *start, *next;
    NSTimeInterval length = 0, nextLength = 0;
    if (!date || ![cal rangeOfUnit:unit startDate:&start interval:&length forDate:date]) return nil;
    NSDate *ahead = [cal dateByAddingUnit:unit value:1 toDate:[start dateByAddingTimeInterval:length / 2] options:0];
    if (!ahead || ![cal rangeOfUnit:unit startDate:&next interval:&nextLength forDate:ahead] ||
        [next compare:start] != NSOrderedDescending) return nil;
    return [[NSDateInterval alloc] initWithStartDate:start endDate:next];
}

NSDateInterval *SGPeriodInterval(SGStatsPeriod period, NSDate *date, NSCalendar *calendar) {
    return unitInterval([calendar copy], periodUnit(period), date);
}

NSDateInterval *SGPeriodStep(SGStatsPeriod period, NSDate *date, NSInteger steps, NSCalendar *calendar) {
    NSCalendar *cal = [calendar copy];
    NSCalendarUnit unit = periodUnit(period);
    NSDateInterval *shown = unitInterval(cal, unit, date);
    if (!shown) return nil;
    // From the middle, so stepping a month never clamps (the 31st) and a week never meets a skipped midnight.
    NSDate *middle = [shown.startDate dateByAddingTimeInterval:shown.duration / 2];
    return unitInterval(cal, unit, [cal dateByAddingUnit:unit value:steps toDate:middle options:0]);
}

NSArray<SGStatBucket *> *SGPeriodBuckets(NSArray<SGPlay *> *plays, SGStatsPeriod period, NSDate *date, NSCalendar *calendar) {
    enum { most = 64 };   // 31 days, or 13 months in a Hebrew leap year
    NSCalendar *cal = [calendar copy];
    NSDateInterval *whole = unitInterval(cal, periodUnit(period), date);
    NSMutableArray<SGStatBucket *> *buckets = [NSMutableArray array];
    if (!whole) return buckets;
    NSCalendarUnit part = period == SGStatsPeriodYear ? NSCalendarUnitMonth : NSCalendarUnitDay;
    int64_t starts[most], end = unixSeconds(whole.endDate);
    NSDate *at = whole.startDate;
    while (buckets.count < most && [at compare:whole.endDate] == NSOrderedAscending) {
        NSDateInterval *piece = unitInterval(cal, part, at);
        if (!piece) break;
        SGStatBucket *bucket = [SGStatBucket new];
        bucket.start = unixSeconds(at);
        bucket.end = MIN(unixSeconds(piece.endDate), end);
        starts[buckets.count] = bucket.start;
        [buckets addObject:bucket];
        at = piece.endDate;
    }
    NSUInteger n = buckets.count;
    if (!n) return buckets;
    int64_t first = starts[0], last = buckets[n - 1].end;
    for (SGPlay *play in plays) {
        if (play.end < first || play.end >= last) continue;
        NSUInteger lo = 0, hi = n;   // the last bucket starting at or before the play's end
        while (hi - lo > 1) {
            NSUInteger mid = (lo + hi) / 2;
            if (starts[mid] <= play.end) lo = mid; else hi = mid;
        }
        buckets[lo].plays++;
        buckets[lo].ms += play.ms;
    }
    return buckets;
}
