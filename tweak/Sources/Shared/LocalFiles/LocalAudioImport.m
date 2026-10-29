// LocalAudioImport.h says what is kept and why.
#import "LocalAudioImport.h"
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

// The list is changed from the import's worker and from the page on main.
static NSObject *listLock(void) {
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; });
    return lock;
}

NSURL *SGLocalAudioFolder(void) {
    return [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
}

NSString *SGLocalAudioNumberedName(NSString *name, NSUInteger attempt) {
    if (attempt <= 1) return name;
    NSString *extension = name.pathExtension;
    NSString *base = name.stringByDeletingPathExtension;
    return extension.length ? [NSString stringWithFormat:@"%@ %lu.%@", base, (unsigned long)attempt, extension]
                            : [NSString stringWithFormat:@"%@ %lu", base, (unsigned long)attempt];
}

// A listed import is its name and the identity of the file the copy made: device, inode and size. A file
// that took the name later (a same-name file from Files, a folder, a link) has another identity, so it is
// not the import: it is neither listed nor deleted.
static NSString *const kName = @"name", *const kDevice = @"device", *const kInode = @"inode", *const kSize = @"size";

// `name` directly in the folder open as `directory`, without following a link. NO unless it is a regular file.
static BOOL statRegular(int directory, NSString *name, struct stat *info) {
    return fstatat(directory, name.fileSystemRepresentation, info, AT_SYMLINK_NOFOLLOW) == 0 && S_ISREG(info->st_mode);
}

static NSDictionary *entryFor(NSString *name, const struct stat *info) {
    return @{kName: name, kDevice: @((long long)info->st_dev), kInode: @((unsigned long long)info->st_ino), kSize: @((long long)info->st_size)};
}

static BOOL entryMatches(NSDictionary *entry, const struct stat *info) {
    return [entry[kDevice] longLongValue] == (long long)info->st_dev && [entry[kInode] unsignedLongLongValue] == (unsigned long long)info->st_ino
        && [entry[kSize] longLongValue] == (long long)info->st_size;
}

// Locked by the caller.
static NSArray<NSDictionary *> *listed(NSUserDefaults *store) {
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    for (id entry in [store arrayForKey:SGKeyLocalAudioImported]) {
        if ([entry isKindOfClass:NSDictionary.class] && [entry[kName] isKindOfClass:NSString.class] && [entry[kInode] isKindOfClass:NSNumber.class]) [entries addObject:entry];
    }
    return entries;
}

static void setListed(NSUserDefaults *store, NSArray<NSDictionary *> *entries) {
    if (entries.count) [store setObject:entries forKey:SGKeyLocalAudioImported];
    else [store removeObjectForKey:SGKeyLocalAudioImported];
}

// The folder opened once, so every check and the unlink after it name the same directory.
static int openFolder(NSURL *folder) {
    return open(folder.fileSystemRepresentation, O_RDONLY | O_DIRECTORY);
}

// The copy refuses to replace a file, so a taken name is found by the copy itself and never raced.
static NSString *copyIn(NSURL *source, NSURL *folder, NSError **error) {
    NSString *name = source.lastPathComponent;
    for (NSUInteger attempt = 1;; attempt++) {
        NSString *candidate = SGLocalAudioNumberedName(name, attempt);
        NSError *failure = nil;
        if ([NSFileManager.defaultManager copyItemAtURL:source toURL:[folder URLByAppendingPathComponent:candidate] error:&failure]) return candidate;
        if (![failure.domain isEqualToString:NSCocoaErrorDomain] || failure.code != NSFileWriteFileExistsError) {
            *error = failure;
            return nil;
        }
    }
}

NSArray<NSString *> *SGLocalAudioImport(NSArray<NSURL *> *urls, NSURL *folder, NSUserDefaults *store, NSArray<NSString *> **failed) {
    NSMutableArray<NSString *> *imported = [NSMutableArray array];
    NSMutableArray<NSString *> *refused = [NSMutableArray array];
    for (NSURL *url in urls) {
        BOOL scoped = [url startAccessingSecurityScopedResource];
        NSError *error = nil;
        NSString *name = copyIn(url, folder, &error);
        if (scoped) [url stopAccessingSecurityScopedResource];
        if (!name) {
            [refused addObject:url.lastPathComponent];
            continue;
        }
        [imported addObject:name];
        // Taken right after the copy; a file that cannot be read back is left unlisted, so never deleted.
        int directory = openFolder(folder);
        struct stat info;
        BOOL made = directory >= 0 && statRegular(directory, name, &info);
        if (directory >= 0) close(directory);
        if (!made) continue;
        @synchronized(listLock()) {
            setListed(store, [listed(store) arrayByAddingObject:entryFor(name, &info)]);
        }
    }
    *failed = refused;
    return imported;
}

NSArray<NSString *> *SGLocalAudioImportedNames(NSURL *folder, NSUserDefaults *store) {
    @synchronized(listLock()) {
        int directory = openFolder(folder);
        NSMutableArray<NSDictionary *> *present = [NSMutableArray array];
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (NSDictionary *entry in listed(store)) {
            struct stat info;
            if (directory >= 0 && [entry[kName] isEqualToString:[entry[kName] lastPathComponent]] && statRegular(directory, entry[kName], &info) && entryMatches(entry, &info)) {
                [present addObject:entry];
                [names addObject:entry[kName]];
            }
        }
        if (directory >= 0) close(directory);
        if (present.count != [store arrayForKey:SGKeyLocalAudioImported].count) setListed(store, present);
        return names;
    }
}

BOOL SGLocalAudioDelete(NSString *name, NSURL *folder, NSUserDefaults *store) {
    @synchronized(listLock()) {
        NSMutableArray<NSDictionary *> *entries = [listed(store) mutableCopy];
        NSDictionary *entry = nil;
        for (NSDictionary *candidate in entries) if ([candidate[kName] isEqualToString:name]) entry = candidate;
        if (!entry || ![name isEqualToString:name.lastPathComponent]) return NO;
        int directory = openFolder(folder);
        if (directory < 0) return NO;
        // Nothing there any more: nothing to delete. Anything else under the name that is not the imported file
        // leaves the entry unlisted and the thing itself alone. unlinkat without AT_REMOVEDIR never removes a
        // folder, so a folder that arrives after the check is refused too.
        struct stat info;
        BOOL gone = fstatat(directory, name.fileSystemRepresentation, &info, AT_SYMLINK_NOFOLLOW) != 0 && errno == ENOENT;
        BOOL ours = !gone && statRegular(directory, name, &info) && entryMatches(entry, &info);
        BOOL removed = ours && unlinkat(directory, name.fileSystemRepresentation, 0) == 0;
        close(directory);
        if (ours && !removed) return NO;
        [entries removeObject:entry];
        setListed(store, entries);
        return gone || removed;
    }
}
