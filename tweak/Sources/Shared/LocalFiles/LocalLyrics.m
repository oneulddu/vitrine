// LocalLyrics.h says what is kept and how a track finds its file.
//
// Playback snapshots names on main and reads files on a serial worker. The native lyrics page also
// reads off main, so links and the bounded sheet cache are protected across both readers.
#import <os/lock.h>
#import "Core/SGCore.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Headers/SPTPlayer.h"
#import "LocalFiles.h"
#import "LocalLyrics.h"

NSString *const SGImportedLRCKey = @"importedLRC";
NSNotificationName const SGImportedLRCDidChangeNotification = @"spotifyglass.localFiles.lrcDidChange";

static NSString *const kErrorDomain = @"spotifyglass.lrc";
static NSString *const kCredit = @"Imported LRC";
// A sheet of lyrics is a few kilobytes; anything near this is not one.
static const NSUInteger kMostBytes = 1024 * 1024;

#pragma mark - the files

static NSString *directory(void) {
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Documents, which the app's backups keep, beside the audio effects' libraries.
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        path = [documents stringByAppendingPathComponent:@"Vitrine/Lyrics"];
    });
    return path;
}

NSArray<NSString *> *SGImportedLRCFiles(void) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory() error:nil]) {
        if ([name.pathExtension.lowercaseString isEqualToString:@"lrc"]) [names addObject:name];
    }
    return [names sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

#pragma mark - the links

static NSDictionary<NSString *, NSString *> *sg_links;
static os_unfair_lock sg_linksLock = OS_UNFAIR_LOCK_INIT;

static NSDictionary<NSString *, NSString *> *allLinks(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        id stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:SGKeyImportedLRCLinks];
        os_unfair_lock_lock(&sg_linksLock);
        sg_links = [stored isKindOfClass:NSDictionary.class] ? stored : @{};
        os_unfair_lock_unlock(&sg_linksLock);
    });
    os_unfair_lock_lock(&sg_linksLock);
    NSDictionary *links = sg_links;
    os_unfair_lock_unlock(&sg_linksLock);
    return links;
}

static void storeLinks(NSDictionary<NSString *, NSString *> *links) {
    os_unfair_lock_lock(&sg_linksLock);
    sg_links = [links copy];
    os_unfair_lock_unlock(&sg_linksLock);
    if (links.count) [NSUserDefaults.standardUserDefaults setObject:links forKey:SGKeyImportedLRCLinks];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyImportedLRCLinks];
}

// A lyrics key carries "#<number>" after the URI once the file's names are edited (LocalFiles.h); the
// link is to the file, so it holds through a rename.
static NSString *bareURI(NSString *uri) {
    if (!SGLocalFileIs(uri)) return nil;
    NSRange mark = [uri rangeOfString:@"#" options:NSBackwardsSearch];
    return mark.location == NSNotFound ? uri : [uri substringToIndex:mark.location];
}

NSString *SGImportedLRCLinkedTo(NSString *uri) {
    NSString *bare = bareURI(uri);
    if (!bare) return nil;
    id name = allLinks()[bare];
    return [name isKindOfClass:NSString.class] ? name : nil;
}

#pragma mark - reading LRC

@interface SGLRCSheet : NSObject
@property (nonatomic, copy) NSString *title, *artist;   // [ti:] and [ar:], nil without them
@property (nonatomic, copy) NSArray<SGKaraokeLine *> *lines;
@property (nonatomic, copy) NSArray<NSNumber *> *starts;   // as Spotify's own page takes them
@property (nonatomic, copy) NSArray<NSString *> *texts;
@property (nonatomic) BOOL synced;
@end

@implementation SGLRCSheet
@end

static NSString *trimmed(NSString *text) {
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

// [01:02], [01:02.3], [01:02.34], [01:02.345], [101:02:34]: a stamp as SGLyricsLRCStamp in
// LyricsSources.h reads it. A line sung more than once carries a stamp per time.
static SGLRCSheet *sheetFrom(NSString *lrc) {
    static NSRegularExpression *tag;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tag = [NSRegularExpression regularExpressionWithPattern:@"^\\[(ti|ar|offset)\\s*:([^\\]]*)\\]" options:NSRegularExpressionCaseInsensitive error:nil];
    });
    NSRegularExpression *stamp = SGLyricsLRCStamp();
    SGLRCSheet *sheet = [SGLRCSheet new];
    NSInteger offset = 0;
    NSMutableArray<NSArray *> *stamped = [NSMutableArray array];   // [ms, text]
    NSMutableArray<NSString *> *plain = [NSMutableArray array];
    for (NSString *raw in [lrc componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *row = trimmed([raw stringByReplacingOccurrencesOfString:@"﻿" withString:@""]);
        NSTextCheckingResult *named = [tag firstMatchInString:row options:0 range:NSMakeRange(0, row.length)];
        if (named) {
            NSString *which = [row substringWithRange:[named rangeAtIndex:1]].lowercaseString;
            NSString *value = trimmed([row substringWithRange:[named rangeAtIndex:2]]);
            if ([which isEqualToString:@"ti"] && value.length) sheet.title = value;
            else if ([which isEqualToString:@"ar"] && value.length) sheet.artist = value;
            else if ([which isEqualToString:@"offset"]) offset = value.integerValue;   // "+250" and "-250" both read
            continue;
        }
        NSArray<NSTextCheckingResult *> *found = [stamp matchesInString:row options:0 range:NSMakeRange(0, row.length)];
        if (!found.count) {
            if (row.length && ![row hasPrefix:@"["]) [plain addObject:row];
            continue;
        }
        NSString *text = trimmed([stamp stringByReplacingMatchesInString:row options:0 range:NSMakeRange(0, row.length) withTemplate:@""]);
        if (!text.length) continue;
        for (NSTextCheckingResult *match in found) {
            [stamped addObject:@[@(SGLyricsLRCStampMs(row, match)), text]];
        }
    }
    if (stamped.count) {
        [stamped sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
            return [a[0] compare:b[0]];
        }];
        NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
        NSMutableArray<NSString *> *texts = [NSMutableArray array];
        // A positive offset brings the lyrics in sooner.
        for (NSArray *line in stamped) {
            [starts addObject:@(MAX([line[0] integerValue] - offset, 0))];
            [texts addObject:line[1]];
        }
        sheet.lines = SGKaraokeEstimatedLines(starts, texts);
        sheet.synced = YES;
        NSArray<NSNumber *> *pageStarts;
        NSArray<NSString *> *pageTexts;
        SGLyricsPageLines(sheet.lines, &pageStarts, &pageTexts);
        sheet.starts = pageStarts;
        sheet.texts = pageTexts;
    } else if (plain.count) {
        sheet.lines = SGKaraokeStaticLines(plain);
        NSMutableArray<NSNumber *> *zeros = [NSMutableArray array];
        for (NSUInteger i = 0; i < plain.count; i++) [zeros addObject:@0];
        sheet.starts = zeros;
        sheet.texts = plain;
    }
    return sheet;
}

// Parsed sheets are bounded independently of the number of imported files.
static NSMutableDictionary<NSString *, SGLRCSheet *> *sg_sheets;
static NSUInteger sg_sheetGeneration;
static const NSUInteger kKeptSheets = 40;

static SGLRCSheet *sheetNamed(NSString *name) {
    NSUInteger generation;
    @synchronized (SGLRCSheet.class) {
        if (!sg_sheets) sg_sheets = [NSMutableDictionary dictionary];
        SGLRCSheet *kept = sg_sheets[name];
        if (kept) return kept;
        generation = sg_sheetGeneration;
    }
    NSString *text = [NSString stringWithContentsOfFile:[directory() stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:nil];
    SGLRCSheet *sheet = text ? sheetFrom(text) : nil;
    if (!sheet) return nil;
    @synchronized (SGLRCSheet.class) {
        if (generation != sg_sheetGeneration) return nil;
        if (sg_sheets.count >= kKeptSheets && !sg_sheets[name]) [sg_sheets removeAllObjects];
        sg_sheets[name] = sheet;
    }
    return sheet;
}

static void forgetSheets(void) {
    @synchronized (SGLRCSheet.class) {
        sg_sheetGeneration++;
        [sg_sheets removeAllObjects];
    }
}

#pragma mark - matching

// Case, diacritics and width ignored, and anything but letters and digits: "Beyoncé – Halo (Live)"
// and "beyonce halo live" fold the same.
static NSString *folded(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return @"";
    NSString *plain = [text stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch locale:nil].lowercaseString;
    return [[plain componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];
}

static NSString *nonEmpty(id value) {
    return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

// A file named "Artist - Title" or "Title - Artist" (a hyphen, en dash or em dash between spaces) with no
// [ti:]: the side equal to the track's title is the title and the other the artist.
static BOOL sheetMatches(SGLRCSheet *sheet, NSString *name, NSString *title, NSArray<NSString *> *artists) {
    NSString *wanted = folded(title);
    if (!wanted.length) return NO;
    NSString *fileTitle = sheet.title, *fileArtist = sheet.artist;
    if (!fileTitle) {
        NSString *base = name.stringByDeletingPathExtension;
        fileTitle = base;
        for (NSString *dash in @[@" - ", @" – ", @" — "]) {
            NSRange split = [base rangeOfString:dash];
            if (split.location == NSNotFound) continue;
            NSString *left = [base substringToIndex:split.location], *right = [base substringFromIndex:NSMaxRange(split)];
            if ([folded(right) isEqualToString:wanted]) {
                fileTitle = right;
                fileArtist = fileArtist ?: left;
            } else if ([folded(left) isEqualToString:wanted]) {
                fileTitle = left;
                fileArtist = fileArtist ?: right;
            }
            break;
        }
    }
    if (![folded(fileTitle) isEqualToString:wanted]) return NO;
    if (!fileArtist.length) return YES;
    NSString *artist = folded(fileArtist);
    for (NSString *one in artists) {
        if ([folded(one) isEqualToString:artist]) return YES;
    }
    return NO;
}

// What a local file is called when no names were given: the player's track model, the tags its metadata
// may carry under other keys when the model's are empty, and last the parts of its URI.
static void localNames(NSString *trackID, NSString **title, NSMutableArray<NSString *> *artists) {
    SPTPlayerTrack *track = SGKaraokeTrackFor(trackID);
    NSDictionary *metadata = [track.metadata isKindOfClass:NSDictionary.class] ? track.metadata : nil;
    NSString *named = nonEmpty(track.trackTitle);
    for (NSString *key in @[@"track_title", @"title", @"name"]) named = named ?: nonEmpty(metadata[key]);
    *title = named ?: SGLocalFileInfo(trackID)[@"title"];

    NSString *artist = nonEmpty(track.artistName);
    for (NSString *key in @[@"artist_name", @"artist"]) artist = artist ?: nonEmpty(metadata[key]);
    if (artist) [artists addObject:artist];
    id listed = metadata[@"artists"];
    for (id one in [listed isKindOfClass:NSArray.class] ? listed : @[]) {
        NSString *each = nonEmpty(one) ?: ([one isKindOfClass:NSDictionary.class] ? nonEmpty(one[@"name"]) : nil);
        if (each) [artists addObject:each];
    }
    for (NSUInteger i = 1; nonEmpty(metadata[[NSString stringWithFormat:@"artist_name:%lu", (unsigned long)i]]); i++) {
        [artists addObject:metadata[[NSString stringWithFormat:@"artist_name:%lu", (unsigned long)i]]];
    }
    NSString *tagged = SGLocalFileInfo(trackID)[@"artist"];
    if (!artists.count && tagged) [artists addObject:tagged];
}

static SGLyricsResult *resultOf(SGLRCSheet *sheet, NSString *title, NSString *artist) {
    if (!sheet.lines.count) return nil;
    SGLyricsResult *result = [SGLyricsResult new];
    result.provider = kCredit;
    result.synced = sheet.synced;
    result.karaokeLines = sheet.lines;
    result.starts = sheet.starts;
    result.texts = sheet.texts;
    result.title = sheet.title ?: title;
    result.artist = sheet.artist ?: artist;
    return result;
}

static SGLyricsResult *lookup(NSString *linked, NSString *title, NSArray<NSString *> *artists) {
    if (linked) return resultOf(sheetNamed(linked), title, artists.firstObject);
    for (NSString *name in SGImportedLRCFiles()) {
        @autoreleasepool {
            SGLRCSheet *sheet = sheetNamed(name);
            if (sheet.lines.count && sheetMatches(sheet, name, title, artists)) return resultOf(sheet, nil, nil);
        }
    }
    return nil;
}

SGLyricsResult *SGImportedLRCFor(NSString *trackID, NSString *title, NSString *artist) {
    NSMutableArray<NSString *> *artists = [NSMutableArray array];
    if (SGLocalFileIs(trackID) && !title.length) localNames(trackID, &title, artists);
    else if (artist.length) [artists addObject:artist];
    return lookup(SGImportedLRCLinkedTo(trackID), title, artists);
}

void SGImportedLRCFetch(NSString *trackID, NSString *title, NSString *artist, void (^done)(SGLyricsResult *)) {
    NSString *resolved = title, *linked = SGImportedLRCLinkedTo(trackID);
    NSMutableArray<NSString *> *artists = [NSMutableArray array];
    if (SGLocalFileIs(trackID) && !resolved.length) localNames(trackID, &resolved, artists);
    else if (artist.length) [artists addObject:artist];
    NSUInteger generation;
    @synchronized (SGLRCSheet.class) { generation = sg_sheetGeneration; }
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("app.vitrine.imported-lyrics", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(queue, ^{
        @autoreleasepool {
            SGLyricsResult *result = lookup(linked, resolved, artists);
            dispatch_async(dispatch_get_main_queue(), ^{
                BOOL changed;
                @synchronized (SGLRCSheet.class) { changed = generation != sg_sheetGeneration; }
                if (changed) { SGImportedLRCFetch(trackID, title, artist, done); return; }
                done(result);
            });
        }
    });
}

SGLyricsAsk SGImportedLRCAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    SGImportedLRCFetch(query.trackID, query.title, query.artist, done);
};

#pragma mark - importing and deleting

static NSError *refusal(NSString *reason) {
    return [NSError errorWithDomain:kErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: reason}];
}

// Once LyricsSources lists the source, the first import and every link put it first in the order.
static void moveToTop(void) {
    if (!SGLyricsProviderFor(SGImportedLRCKey)) return;
    NSMutableArray<NSString *> *order = [SGLyricsOrder() mutableCopy];
    [order removeObject:SGImportedLRCKey];
    [order insertObject:SGImportedLRCKey atIndex:0];
    SGLyricsSetOrder(order);
}

static void changed(void) {
    forgetSheets();
    [NSNotificationCenter.defaultCenter postNotificationName:SGImportedLRCDidChangeNotification object:nil];
}

// The name it came with, "/" made safe, and " (2)", " (3)" and on when one by that name is kept.
static NSString *freeName(NSString *given) {
    NSString *name = [given stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    NSString *base = name.stringByDeletingPathExtension, *extension = name.pathExtension;
    if (!base.length || [base hasPrefix:@"."]) base = [@"Lyrics" stringByAppendingString:base];
    name = [base stringByAppendingPathExtension:extension];
    for (NSUInteger n = 2; [NSFileManager.defaultManager fileExistsAtPath:[directory() stringByAppendingPathComponent:name]]; n++) {
        name = [[NSString stringWithFormat:@"%@ (%lu)", base, (unsigned long)n] stringByAppendingPathExtension:extension];
    }
    return name;
}

static NSString *storeImportedText(NSString *text, NSURL *url, NSString *uri, NSError **error) {
    BOOL first = SGImportedLRCFiles().count == 0;
    NSString *name = freeName(url.lastPathComponent);
    NSError *writeError = nil;
    [NSFileManager.defaultManager createDirectoryAtPath:directory() withIntermediateDirectories:YES attributes:nil error:&writeError];
    if (![text writeToFile:[directory() stringByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
        SGLog(@"lrc: %@ not written: %@", name, writeError);
        if (error) *error = writeError;
        return nil;
    }
    NSString *bare = bareURI(uri);
    if (bare) {
        NSMutableDictionary *links = [allLinks() mutableCopy];
        links[bare] = name;
        storeLinks(links);
    }
    if (first || bare) moveToTop();
    SGLog(@"lrc: imported %@%@", name, bare ? [@" for " stringByAppendingString:bare] : @"");
    changed();
    return name;
}

void SGImportLRC(NSURL *url, NSString *uri, void (^completion)(NSString *, NSError *)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL scoped = [url startAccessingSecurityScopedResource];
        NSError *error;
        NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:&error];
        NSData *data = [handle readDataUpToLength:kMostBytes + 1 error:&error];
        NSError *closeError;
        if (handle && ![handle closeAndReturnError:&closeError]) error = error ?: closeError;
        if (scoped) [url stopAccessingSecurityScopedResource];
        NSString *reason = nil, *text = nil;
        if (error || !data) reason = error.localizedDescription ?: @"The file could not be read.";
        else if (!data.length) reason = @"The file is empty.";
        else if (data.length > kMostBytes) reason = @"The file is over 1 MB, too large for lyrics.";
        else {
            text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                ?: [[NSString alloc] initWithData:data encoding:NSUTF16StringEncoding];
            if (!text) reason = @"The file is not UTF-8 or UTF-16 text.";
            else if (![text containsString:@"]"]) reason = @"The file has no LRC tags or timestamps.";
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError *failure = reason ? refusal(reason) : nil;
            NSString *name = failure ? nil : storeImportedText(text, url, uri, &failure);
            completion(name, failure);
        });
    });
}

BOOL SGDeleteImportedLRC(NSString *name) {
    if (!name.length || name.pathComponents.count != 1) return NO;
    NSError *error = nil;
    if (![NSFileManager.defaultManager removeItemAtPath:[directory() stringByAppendingPathComponent:name] error:&error]) {
        SGLog(@"lrc: %@ not deleted: %@", name, error);
        return NO;
    }
    NSMutableDictionary *links = [allLinks() mutableCopy];
    [links removeObjectsForKeys:[links allKeysForObject:name]];
    storeLinks(links);
    changed();
    return YES;
}
