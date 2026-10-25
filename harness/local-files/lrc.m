// Checks LocalLyrics.m as the tweak compiles it: an .lrc file imported (the refusals, the name kept, a
// taken name numbered), read into lines (several stamps on a line, the fraction's forms, the offset,
// untimed text), linked to a local file and matched by title and artist, folded, with the sides of an
// "Artist - Title" name worked out from the track. Runs in its own home, so nothing of the Mac's is
// touched. Exits non-zero on the first wrong answer.
#import <UIKit/UIKit.h>
#import "Shared/LocalFiles/LocalFiles.h"
#import "Shared/LocalFiles/LocalLyrics.h"
#import "import.h"
#import <objc/runtime.h>
#include <stdatomic.h>

#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #cond); exit(1); } } while (0)

// What LyricsSources.m and KaraokeSource.x give the tweak, here as little as the file needs.
@implementation SGLyricsResult
@end
@implementation SGLyricsQuery
@end
@implementation SGLyricsProvider
@end
static NSArray<NSString *> *sg_order;
NSArray<NSString *> *SGLyricsOrder(void) { return sg_order ?: @[]; }
void SGLyricsSetOrder(NSArray<NSString *> *keys) { sg_order = keys; }
SGLyricsProvider *SGLyricsProviderFor(NSString *key) {
    SGLyricsProvider *provider = [SGLyricsProvider new];
    provider.key = key;
    return provider;
}
void SGLyricsPageLines(NSArray<SGKaraokeLine *> *lines, NSArray<NSNumber *> **starts, NSArray<NSString *> **texts) {
    NSMutableArray *at = [NSMutableArray array], *said = [NSMutableArray array];
    for (SGKaraokeLine *line in lines) {
        [at addObject:@(line.start)];
        [said addObject:SGKaraokeLineText(line)];
    }
    *starts = at;
    *texts = said;
}
SPTPlayerTrack *SGKaraokeTrackFor(NSString *trackID) { return nil; }

static NSURL *temporaryDirectory;
static NSURL *fileNamed(NSString *name, NSData *data) {
    NSURL *url = [temporaryDirectory URLByAppendingPathComponent:name];
    [data writeToURL:url atomically:YES];
    return url;
}

static NSURL *lrc(NSString *name, NSString *text) {
    return fileNamed(name, [text dataUsingEncoding:NSUTF8StringEncoding]);
}

// Hold a real file read after it obtained the old bytes, while main deletes/reimports its name.
static void invalidationCheck(void) {
    NSString *uri = @"spotify:local:Race:Album:Track:120";
    NSURL *source = lrc(@"race.lrc", @"[00:01]Old lyrics");
    CHECK(importLRC(source, uri, nil));
    dispatch_semaphore_t read = dispatch_semaphore_create(0), resume = dispatch_semaphore_create(0), finished = dispatch_semaphore_create(0);
    SEL selector = @selector(stringWithContentsOfFile:encoding:error:);
    Method method = class_getClassMethod(NSString.class, selector);
    IMP original = method_getImplementation(method);
    static atomic_bool intercept;
    atomic_store(&intercept, true);
    IMP blocked = imp_implementationWithBlock(^id(id receiver, NSString *path, NSStringEncoding encoding, NSError **error) {
        id text = ((id (*)(id, SEL, id, NSStringEncoding, NSError **))original)(receiver, selector, path, encoding, error);
        if ([path.lastPathComponent isEqual:@"race.lrc"] && !NSThread.isMainThread && atomic_exchange(&intercept, false)) {
            dispatch_semaphore_signal(read);
            if (dispatch_semaphore_wait(resume, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC))) {
                fprintf(stderr, "cache read barrier timed out\n"); exit(1);
            }
        }
        return text;
    });
    method_setImplementation(method, blocked);
    __block SGLyricsResult *stale;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        stale = SGImportedLRCFor(uri, @"Track", @"Race");
        dispatch_semaphore_signal(finished);
    });
    CHECK(dispatch_semaphore_wait(read, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    CHECK(SGDeleteImportedLRC(@"race.lrc"));
    CHECK([importLRC(lrc(@"race.lrc", @"[00:01]Replacement lyrics"), uri, nil) isEqual:@"race.lrc"]);
    dispatch_semaphore_signal(resume);
    CHECK(dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    method_setImplementation(method, original);
    imp_removeBlock(blocked);
    CHECK(!stale);
    CHECK([SGImportedLRCFor(uri, @"Track", @"Race").texts.firstObject isEqual:@"Replacement lyrics"]);
    CHECK(SGDeleteImportedLRC(@"race.lrc"));
}

int main(void) {
    @autoreleasepool {
        temporaryDirectory = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        CHECK([NSFileManager.defaultManager createDirectoryAtURL:temporaryDirectory withIntermediateDirectories:YES attributes:nil error:nil]);
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        [NSFileManager.defaultManager removeItemAtPath:[documents stringByAppendingPathComponent:@"Vitrine/Lyrics"] error:nil];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyImportedLRCLinks];
        sg_order = @[@"lrclib"];
        NSError *error = nil;

        // Refusals: empty, too large, no "]".
        CHECK(!importLRC(lrc(@"empty.lrc", @""), nil, &error) && error);
        CHECK(!importLRC(fileNamed(@"big.lrc", [NSMutableData dataWithLength:1024 * 1024 + 1]), nil, &error));
        CHECK(!importLRC(lrc(@"words.lrc", @"just some words"), nil, &error));
        NSURL *huge = fileNamed(@"sparse.lrc", [NSData data]);
        NSFileHandle *sparse = [NSFileHandle fileHandleForWritingToURL:huge error:nil];
        CHECK([sparse truncateAtOffset:8ULL * 1024 * 1024 * 1024 error:nil]);
        CHECK([sparse closeAndReturnError:nil]);
        CHECK(!importLRC(huge, nil, &error) && [error.localizedDescription isEqual:@"The file is over 1 MB, too large for lyrics."]);
        CHECK(SGImportedLRCFiles().count == 0);

        // Several stamps on a line, every fraction form, an offset, a line with no text skipped.
        NSString *sheet = @"﻿[ti:Halo]\n[ar:Beyoncé]\n[offset:+500]\n[00:10.5][01:00:250]Remember\n[00:20.25]those walls\n[00:30]\n[1:05.123]I built\n";
        NSString *name = importLRC(lrc(@"halo.lrc", sheet), nil, &error);
        CHECK([name isEqualToString:@"halo.lrc"]);
        CHECK([SGLyricsOrder().firstObject isEqualToString:SGImportedLRCKey]);   // the first import goes on top
        SGLyricsResult *found = SGImportedLRCFor(@"spotify:track:x", @"HALO", @"beyonce");
        CHECK(found.synced && found.karaokeLines.count == 4);
        NSArray<NSNumber *> *starts = [found.karaokeLines valueForKey:@"start"];
        CHECK([starts isEqualToArray:(@[@10000, @19750, @59750, @64623])]);
        CHECK([SGKaraokeLineText(found.karaokeLines[2]) isEqualToString:@"Remember"]);
        CHECK([found.title isEqualToString:@"Halo"] && [found.provider isEqualToString:@"Imported LRC"]);
        CHECK(!SGImportedLRCFor(@"spotify:track:x", @"Halo", @"Someone else"));
        CHECK(!SGImportedLRCFor(@"spotify:track:x", nil, @"Beyoncé"));   // never without a title

        // A taken name is numbered.
        CHECK([importLRC(lrc(@"halo.lrc", sheet), nil, &error) isEqualToString:@"halo (2).lrc"]);
        CHECK(SGDeleteImportedLRC(@"halo (2).lrc"));

        // "Artist - Title" and "Title – Artist" with no tags: the sides come from the track.
        importLRC(lrc(@"Daft Punk - One More Time.lrc", @"[00:01.00]One more time"), nil, &error);
        importLRC(lrc(@"Around the World – Daft Punk.lrc", @"[00:01.00]Around the world"), nil, &error);
        CHECK(SGImportedLRCFor(@"spotify:track:y", @"one more time!", @"DAFT PUNK"));
        CHECK(SGImportedLRCFor(@"spotify:track:y", @"Around The World", @"Daft Punk"));
        CHECK(!SGImportedLRCFor(@"spotify:track:y", @"One More Time", @"Justice"));
        CHECK(!SGImportedLRCFor(@"spotify:track:y", @"Discovery", @"Daft Punk"));

        // A local file named by its URI; one linked has its file whatever the names say, and keeps it
        // through a rename's lyrics key. Untimed text drops the lines that open with "[".
        NSString *uri = @"spotify:local:Daft+Punk:Discovery:One+More+Time:320";
        CHECK(SGImportedLRCFor(uri, nil, nil));
        NSString *other = @"spotify:local:::Track+01:200";
        CHECK(!SGImportedLRCFor(other, nil, nil));
        sg_order = @[@"lrclib", SGImportedLRCKey];
        NSString *plain = importLRC(lrc(@"notes.lrc", @"[by:me]\nFirst line\n\nSecond line\n[x] dropped"), other, &error);
        CHECK([SGLyricsOrder().firstObject isEqualToString:SGImportedLRCKey]);   // a link goes on top
        CHECK([SGImportedLRCLinkedTo([other stringByAppendingString:@"#123"]) isEqualToString:plain]);
        found = SGImportedLRCFor(other, nil, nil);
        CHECK(found && !found.synced && found.karaokeLines.count == 2 && [found.title isEqualToString:@"Track 01"]);
        CHECK(!importLRC(lrc(@"skip.lrc", @"[00:01]x"), @"spotify:track:z", &error) || !SGImportedLRCLinkedTo(@"spotify:track:z"));

        // Deleting the file takes its link and its lyrics.
        CHECK(SGDeleteImportedLRC(plain));
        CHECK(!SGImportedLRCLinkedTo(other) && !SGImportedLRCFor(other, nil, nil));
        CHECK(![[NSUserDefaults.standardUserDefaults dictionaryForKey:SGKeyImportedLRCLinks] count]);

        // UTF-16 is read and kept as UTF-8.
        NSString *utf16 = importLRC(fileNamed(@"wide.lrc", [@"[ti:Wide]\n[00:02.00]wide" dataUsingEncoding:NSUTF16StringEncoding]), nil, &error);
        NSString *kept = [NSString stringWithContentsOfFile:[documents stringByAppendingPathComponent:[@"Vitrine/Lyrics" stringByAppendingPathComponent:utf16]]
                                                   encoding:NSUTF8StringEncoding error:nil];
        CHECK([kept hasPrefix:@"[ti:Wide]"]);
        invalidationCheck();
        [NSFileManager.defaultManager removeItemAtURL:temporaryDirectory error:nil];
        printf("lrc: all checks passed\n");
    }
    return 0;
}
