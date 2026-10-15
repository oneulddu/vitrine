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
#import <CommonCrypto/CommonDigest.h>

static const NSUInteger kKept = 200;

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
        unsigned char digest[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(identity.bytes, (CC_LONG)identity.length, digest);
        NSMutableString *name = [NSMutableString stringWithString:@"local-hash-"];
        for (NSUInteger i = 0; i < sizeof(digest); i++) [name appendFormat:@"%02x", digest[i]];
        track = name;
    }
    return [folder() URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@.json", track, tag]];
}

static NSArray<NSURL *> *filesIn(NSURL *directory) {
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
    [sg_translationJobs removeObjectForKey:@[track, language]];
    dispatch_sync(writes(), ^{
        BOOL removed = [NSFileManager.defaultManager removeItemAtURL:file error:nil];
        rememberUnsaved(file, removed || ![NSFileManager.defaultManager fileExistsAtPath:file.path] ? nil : @{});
    });
}

void SGLyricsSyncSavedTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines) {
    NSURL *file = fileFor(track, language);
    if (!file || !lines.count) return;
    __block NSDictionary *saved = nil;
    // A view notified just after a batch must read that batch, not the preceding async write.
    dispatch_sync(writes(), ^{
        saved = sg_unsavedTranslations[file];
        if (saved) return;
        NSData *data = [NSData dataWithContentsOfURL:file];
        id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if ([value isKindOfClass:NSDictionary.class]) saved = value;
    });
    for (SGKaraokeLine *line in lines) {
        id translation = saved[SGKaraokeLineText(line) ?: @""];
        BOOL has = [translation isKindOfClass:NSString.class] && [translation length];
        if (line.translationMade) {
            line.translation = has ? translation : nil;
            line.translationMade = has;
        } else if (!line.translation.length && has) {
            line.translation = translation;
            line.translationMade = YES;
        }
    }
}

void SGLyricsSaveTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines) {
    NSURL *file = fileFor(track, language);
    if (!file) return;
    NSMutableDictionary<NSString *, NSString *> *saved = [NSMutableDictionary dictionary];
    for (SGKaraokeLine *line in lines) {
        NSString *text = SGKaraokeLineText(line);
        if (text.length && line.translationMade && line.translation.length) saved[text] = line.translation;
    }
    if (!saved.count) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:saved options:0 error:nil];
    // One at a time, in the order asked: a song is saved after every batch, and an older write must not land last.
    dispatch_async(writes(), ^{
        [NSFileManager.defaultManager createDirectoryAtURL:folder() withIntermediateDirectories:YES attributes:nil error:nil];
        BOOL written = [data writeToURL:file atomically:YES];
        rememberUnsaved(file, written ? nil : saved);
        if (written) trim(folder());
    });
}

static NSString *summary(void) {
    NSArray<NSURL *> *all = files();
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

SGModRow *SGSavedTranslationsRow(void) {
    return SGStatActionRow(SGL(@"settings.translation.savedtranslations.title", @"Saved translations"), SGL(@"settings.translation.savedtranslations.aisubtitle", @"Saved translations, pronunciations and cultural notes"),
                           ^NSString *{ return summary(); }, ^{
        if (!files().count) return;
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
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(tuple.bytes, (CC_LONG)tuple.length, digest);
    NSMutableString *name = [NSMutableString stringWithCapacity:64];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [name appendFormat:@"%02x", digest[i]];
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
NSDictionary<NSString *, NSString *> *SGLyricsSavedAI(NSString *kind, NSString *track, NSString *variant) {
    NSURL *file = aiFile(kind, track, variant);
    if (!file) return nil;
    __block NSDictionary *answer = nil;
    dispatch_sync(writes(), ^{
        NSNumber *size = nil;
        if (![file getResourceValue:&size forKey:NSURLFileSizeKey error:nil] || size.unsignedLongLongValue > 1024 * 1024) return;
        NSData *data = [NSData dataWithContentsOfURL:file];
        id saved = data && data.length <= 1024 * 1024 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (validAI(saved)) answer = saved;
    });
    return answer;
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
    });
}

void SGLyricsDeleteSavedTranslations(void) {
    [sg_translationJobs removeAllObjects];
    SGLyricsAIForgotten();
    dispatch_sync(writes(), ^{
        [sg_unsavedTranslations removeAllObjects];
        [sg_unsavedOrder removeAllObjects];
        [NSFileManager.defaultManager removeItemAtURL:folder() error:nil];
        [NSFileManager.defaultManager removeItemAtURL:aiFolder() error:nil];
    });
}
