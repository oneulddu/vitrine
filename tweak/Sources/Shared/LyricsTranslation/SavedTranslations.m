// Translations kept on disk, whichever way they were made: one small JSON file a song and language in
// Caches/Vitrine/Translations, each line's text to its translation, so a song comes back translated after
// a relaunch and lyrics from another source still find their lines. The newest kKept files stay; iOS may
// clear Caches when it runs low, which costs a translation again. Pronunciation and cultural notes
// live beside these in Caches/Vitrine/AI, with their own limit of 200 files.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Lyrics/Lyrics.h"
#import "AIServicesInternal.h"
#import "Core/SGFileHash.h"

static const NSUInteger kKept = 200;
// Store-queue ordering stops at delivery to main. A mutation requested meanwhile
// also retires read results waiting to be applied to the live lyric objects.
@interface SGTranslationReadVersion : NSObject
@property (nonatomic) NSUInteger mutation, readers;
@end
@implementation SGTranslationReadVersion
@end
// Guarded by the class lock. Keep versions only while reads are outstanding, not
// for every song visited this launch. Delete-all also invalidates reads of absent files.
static NSMutableDictionary<NSURL *, SGTranslationReadVersion *> *sg_readVersions;
static NSUInteger sg_deleteEpoch;

static void translationMutated(NSURL *file) {
    @synchronized (SGTranslationReadVersion.class) {
        SGTranslationReadVersion *version = sg_readVersions[file];
        version.mutation++;
    }
}

NSNotificationName const SGLyricsTranslationSavedNotification = @"spotifyglass.lyricsTranslationSaved";
NSNotificationName const SGLyricsSavedSummaryDidChangeNotification = @"spotifyglass.lyricsSavedSummaryDidChange";

// Only main reads/publishes these; directory enumeration stays on writes().
static NSString *sg_savedSummary;
static NSUInteger sg_savedCount;
static void refreshSummary(void); // called on writes(); coalesces queued mutations

static NSURL *cacheRoot(void) {
#ifdef SG_LYRICS_TEST_STORE
    // The offline harness owns an isolated folder and never trims the user's saved songs.
    extern NSURL *SGLyricsTestCacheRoot(void);
    return SGLyricsTestCacheRoot();
#else
    NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    return [caches URLByAppendingPathComponent:@"Vitrine" isDirectory:YES];
#endif
}
static NSURL *folder(void) { return [cacheRoot() URLByAppendingPathComponent:@"Translations" isDirectory:YES]; }
static NSURL *aiFolder(void) { return [cacheRoot() URLByAppendingPathComponent:@"AI" isDirectory:YES]; }
static dispatch_queue_t writes(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("vitrine.translations", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

static NSURL *fileFor(NSString *track, NSString *language) {
    if (![track isKindOfClass:NSString.class] || !track.length || track.length > 4096 ||
        ![language isKindOfClass:NSString.class] || !SGGoogleTargetLanguage(language)) return nil;
    NSCharacterSet *unsafe = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"].invertedSet;
    NSString *tag = [[language componentsSeparatedByCharactersInSet:unsafe] componentsJoinedByString:@"_"];
    NSString *name = [NSString stringWithFormat:@"%@.%@.json", track, tag];
    // Keep every previously valid filename, including long local URIs. Only a filename exceeding
    // the filesystem's 255-byte limit or containing a path separator needs a bounded hash.
    if ([name lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 255 || [track containsString:@"/"] ||
        [track containsString:@"\\"] || [track isEqual:@"."] || [track isEqual:@".."]) {
        NSData *identity = [track dataUsingEncoding:NSUTF8StringEncoding];
        track = [@"local-hash-" stringByAppendingString:SGDataSHA256(identity)];
    }
    return [folder() URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@.json", track, tag]];
}

static NSArray<NSURL *> *filesIn(NSURL *directory) {
#ifdef SG_LYRICS_TEST_STORE
    extern void SGLyricsTestStoreEnumeration(void);
    SGLyricsTestStoreEnumeration();
#endif
    return [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory includingPropertiesForKeys:@[NSURLContentModificationDateKey, NSURLFileSizeKey]
                                                          options:NSDirectoryEnumerationSkipsHiddenFiles error:nil] ?: @[];
}

static NSArray<NSURL *> *files(void) { return [filesIn(folder()) arrayByAddingObjectsFromArray:filesIn(aiFolder())]; }
static void trim(NSURL *directory) {
    NSArray<NSURL *> *all = filesIn(directory);
    if (all.count <= kKept) return;
    NSArray<NSURL *> *oldestFirst = [all sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        NSDate *da = nil, *db = nil;
        [a getResourceValue:&da forKey:NSURLContentModificationDateKey error:nil];
        [b getResourceValue:&db forKey:NSURLContentModificationDateKey error:nil];
        return [da ?: NSDate.distantPast compare:db ?: NSDate.distantPast];
    }];
    for (NSUInteger i = 0; i < all.count - kKept; i++) [NSFileManager.defaultManager removeItemAtURL:oldestFirst[i] error:nil];
}

// A disk failure must not erase a result already shown. The serial store queue also owns these
// session-only answers (or an empty tombstone after a failed delete), with the same 200-song bound.
static NSMutableDictionary<NSURL *, NSDictionary *> *sg_unsavedTranslations;
static NSMutableArray<NSURL *> *sg_unsavedOrder;
static void rememberUnsaved(NSURL *file, NSDictionary *answer) {
    if (!sg_unsavedTranslations) { sg_unsavedTranslations = [NSMutableDictionary dictionary]; sg_unsavedOrder = [NSMutableArray array]; }
    [sg_unsavedOrder removeObject:file];
    [sg_unsavedTranslations removeObjectForKey:file];
    if (!answer) return;
    if (sg_unsavedOrder.count >= kKept) {
        [sg_unsavedTranslations removeObjectForKey:sg_unsavedOrder.firstObject];
        [sg_unsavedOrder removeObjectAtIndex:0];
    }
    sg_unsavedTranslations[file] = [answer copy];
    [sg_unsavedOrder addObject:file];
}

// The token belongs to a song/language, not a view. All calls and callback checks are on main.
static NSMutableDictionary<NSArray *, NSNumber *> *sg_translationJobs;
static NSUInteger sg_nextTranslationJob;
NSUInteger SGLyricsBeginTranslation(NSString *track, NSString *language) {
    if (!fileFor(track, language)) return 0;
    if (!sg_translationJobs) sg_translationJobs = [NSMutableDictionary dictionary];
    NSUInteger token = ++sg_nextTranslationJob;
    if (!token) token = ++sg_nextTranslationJob;
    sg_translationJobs[@[track, language]] = @(token);
    return token;
}
BOOL SGLyricsTranslationIsCurrent(NSString *track, NSString *language, NSUInteger token) {
    return token && track && language && [sg_translationJobs[@[track, language]] unsignedIntegerValue] == token;
}
void SGLyricsEndTranslation(NSString *track, NSString *language, NSUInteger token) {
    if (SGLyricsTranslationIsCurrent(track, language, token)) [sg_translationJobs removeObjectForKey:@[track, language]];
}
void SGLyricsDeleteTranslation(NSString *track, NSString *language) {
    NSURL *file = fileFor(track, language);
    if (!file) return;
    translationMutated(file);
    [sg_translationJobs removeObjectForKey:@[track, language]];
    dispatch_sync(writes(), ^{
        BOOL removed = [NSFileManager.defaultManager removeItemAtURL:file error:nil];
        rememberUnsaved(file, removed || ![NSFileManager.defaultManager fileExistsAtPath:file.path] ? nil : @{});
        refreshSummary();
    });
}

static NSDictionary *readTranslation(NSURL *file) {
    if (!file) return nil;
    NSDictionary *saved = sg_unsavedTranslations[file];
    if (saved) return saved;
    NSData *data = [NSData dataWithContentsOfURL:file];
    id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}
static void applyTranslation(NSDictionary *saved, NSArray<SGKaraokeLine *> *lines) {
    for (SGKaraokeLine *line in lines) {
        id translation = saved[SGKaraokeLineText(line) ?: @""];
        BOOL has = [translation isKindOfClass:NSString.class] &&
            [translation stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length;
        if (line.translationMade) {
            line.translation = has ? translation : nil;
            line.translationMade = has;
        } else if (!line.translation.length && has) {
            line.translation = translation;
            line.translationMade = YES;
        }
    }
}

void SGLyricsSyncSavedTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines) {
    NSURL *file = fileFor(track, language);
    if (!file || !lines.count) return;
    __block NSDictionary *saved;
    dispatch_sync(writes(), ^{ saved = readTranslation(file); });
    applyTranslation(saved, lines);
}

static void loadTranslation(NSURL *file, NSArray<SGKaraokeLine *> *lines,
                            BOOL (^current)(void), void (^done)(void), BOOL mayReload) {
    SGTranslationReadVersion *version = nil;
    NSUInteger mutation, epoch;
    @synchronized (SGTranslationReadVersion.class) {
        if (file) {
            if (!sg_readVersions) sg_readVersions = [NSMutableDictionary dictionary];
            version = sg_readVersions[file];
            if (!version) sg_readVersions[file] = version = [SGTranslationReadVersion new];
            version.readers++;
        }
        mutation = version.mutation;
        epoch = sg_deleteEpoch;
    }
    dispatch_async(writes(), ^{
        NSDictionary *saved = readTranslation(file);
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL changed;
            @synchronized (SGTranslationReadVersion.class) {
                changed = file && (mutation != version.mutation || epoch != sg_deleteEpoch);
                if (version && --version.readers == 0) [sg_readVersions removeObjectForKey:file];
            }
            if (!current()) return;
            if (changed) {
                if (mayReload) loadTranslation(file, lines, current, done, NO);
                // A second intervening mutation retires this attempt too; finish without
                // overwriting live lines. Its newer save/delete owns the current state.
                else done();
                return;
            }
            if (file) applyTranslation(saved, lines);
            done();
        });
    });
}

void SGLyricsLoadTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines,
                             BOOL (^current)(void), void (^done)(void)) {
    loadTranslation(fileFor(track, language), lines, current, done, YES);
}

void SGLyricsSaveTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines) {
    NSURL *file = fileFor(track, language);
    if (!file) return;
    NSMutableDictionary<NSString *, NSString *> *saved = [NSMutableDictionary dictionary];
    for (SGKaraokeLine *line in lines) {
        NSString *text = SGKaraokeLineText(line);
        if (text.length && line.translationMade &&
            [line.translation stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) saved[text] = line.translation;
    }
    if (!saved.count) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:saved options:0 error:nil];
    translationMutated(file);
    // One at a time, in the order asked: a song is saved after every batch, and an older write must not land last.
    dispatch_async(writes(), ^{
        [NSFileManager.defaultManager createDirectoryAtURL:folder() withIntermediateDirectories:YES attributes:nil error:nil];
        BOOL written = [data writeToURL:file atomically:YES];
        rememberUnsaved(file, written ? nil : saved);
        if (written) trim(folder());
        refreshSummary();
    });
    // Readers enqueue after this write, preserving read-after-write order without blocking main.
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationSavedNotification object:track
                                                      userInfo:@{@"language": language}];
}

static NSString *summary(NSArray<NSURL *> *all) {
    if (!all.count) return SGL(@"settings.translation.savedtranslations.value.none", @"None");
    long long bytes = 0;
    for (NSURL *file in all) {
        NSNumber *size;
        [file getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        bytes += size.longLongValue;
    }
    return [NSString stringWithFormat:SGL(@"settings.translation.savedtranslations.value.format", @"%lu · %@"), (unsigned long)all.count,
            [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile]];
}

static void refreshSummary(void) {
    static BOOL queued;
    if (queued) return;
    queued = YES;
    dispatch_async(writes(), ^{
        queued = NO;
        NSArray<NSURL *> *all = files();
        NSString *value = summary(all);
        dispatch_async(dispatch_get_main_queue(), ^{
            sg_savedCount = all.count;
            if ([sg_savedSummary isEqualToString:value]) return;
            sg_savedSummary = value;
            // The live settings row reads this cache on its next value refresh.
            [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsSavedSummaryDidChangeNotification object:nil];
        });
    });
}

SGModRow *SGSavedTranslationsRow(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ dispatch_async(writes(), ^{ refreshSummary(); }); });
    return SGStatActionRow(SGL(@"settings.translation.savedtranslations.title", @"Saved translations"), SGL(@"settings.translation.savedtranslations.aisubtitle", @"Saved translations, pronunciations and cultural notes"),
                           ^NSString *{ return sg_savedSummary; }, ^{
        if (!sg_savedCount) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.translation.savedtranslations.alert.title", @"Delete saved translations?")
            message:SGL(@"settings.translation.savedtranslations.alert.message", @"Songs translated before are translated again the next time you ask.") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.delete", @"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            SGLyricsDeleteSavedTranslations();
            SGLog(@"translation: saved translations deleted");
            [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
}

// Hash the tuple instead of cleaning characters: a slash in a track ID cannot escape the folder,
// and different punctuation in identifiers must not make two songs share a file.
static NSURL *aiFile(NSString *kind, NSString *track, NSString *variant) {
    if ((![kind isEqual:@"pronunciation"] && ![kind isEqual:@"notes"]) || ![track isKindOfClass:NSString.class] || !track.length || track.length > 1024 ||
        ![variant isKindOfClass:NSString.class] || !variant.length || variant.length > 64) return nil;
    // Notation zero follows the current translation language. Keep its letters separate when that
    // language changes, while callers continue to identify the notation by the number zero.
    NSArray *identity = [kind isEqual:@"pronunciation"] && [variant isEqual:@"0"]
        ? @[kind, track, variant, SGLyricsGeminiLanguage()] : @[kind, track, variant];
    NSData *tuple = [NSJSONSerialization dataWithJSONObject:identity options:0 error:nil];
    NSString *name = SGDataSHA256(tuple);
    return [aiFolder() URLByAppendingPathComponent:[name stringByAppendingString:@".json"]];
}
static BOOL validAI(id values) {
    if (![values isKindOfClass:NSDictionary.class] || [values count] > 2000) return NO;
    NSUInteger size = 0;
    for (id text in values) {
        id value = values[text];
        if (![text isKindOfClass:NSString.class] || ![value isKindOfClass:NSString.class] || [text length] > 64000 || [value length] > 64000) return NO;
        size += [text length] + [value length];
        if (size > 256000) return NO;
    }
    return YES;
}
static NSDictionary *readAI(NSURL *file) {
    if (!file) return nil;
    NSNumber *size = nil;
    if (![file getResourceValue:&size forKey:NSURLFileSizeKey error:nil] || size.unsignedLongLongValue > 1024 * 1024) return nil;
    NSData *data = [NSData dataWithContentsOfURL:file];
    id saved = data && data.length <= 1024 * 1024 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return validAI(saved) ? saved : nil;
}
NSDictionary<NSString *, NSString *> *SGLyricsSavedAI(NSString *kind, NSString *track, NSString *variant) {
    NSURL *file = aiFile(kind, track, variant);
    __block NSDictionary *answer = nil;
    dispatch_sync(writes(), ^{ answer = readAI(file); });
    return answer;
}
void SGLyricsLoadSavedAI(NSString *kind, NSString *track, NSString *variant, void (^done)(NSDictionary *)) {
    NSURL *file = aiFile(kind, track, variant);
    dispatch_async(writes(), ^{
        NSDictionary *answer = readAI(file);
        dispatch_async(dispatch_get_main_queue(), ^{ done(answer); });
    });
}
void SGLyricsSaveAI(NSString *kind, NSString *track, NSString *variant, NSDictionary<NSString *, NSString *> *byLine) {
    NSURL *file = aiFile(kind, track, variant);
    if (!file || !validAI(byLine)) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:byLine options:0 error:nil];
    if (!data || data.length > 1024 * 1024) return;
    dispatch_async(writes(), ^{
        [NSFileManager.defaultManager createDirectoryAtURL:aiFolder() withIntermediateDirectories:YES attributes:nil error:nil];
        [data writeToURL:file atomically:YES];
        trim(aiFolder());
        refreshSummary();
    });
}

void SGLyricsDeleteSavedTranslations(void) {
    @synchronized (SGTranslationReadVersion.class) { sg_deleteEpoch++; }
    [sg_translationJobs removeAllObjects];
    SGLyricsAIForgotten();
    dispatch_sync(writes(), ^{
        [sg_unsavedTranslations removeAllObjects];
        [sg_unsavedOrder removeAllObjects];
        [NSFileManager.defaultManager removeItemAtURL:folder() error:nil];
        [NSFileManager.defaultManager removeItemAtURL:aiFolder() error:nil];
        refreshSummary();
    });
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsAIResultDidChangeNotification object:nil];
}
