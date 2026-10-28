#import "AlbumSpotifyCounts.h"

static const NSUInteger kMaxTracksPerAlbum = 500, kMaxCachedAlbums = 64, kMaxCacheBytes = 2 * 1024 * 1024;
static const NSUInteger kMaxPendingAlbums = 16, kMaxAlbumWaiters = 16;
static const NSTimeInterval kCountLifetimeSeconds = 24 * 60 * 60, kUnavailableLifetimeSeconds = 5 * 60;
// Extended-metadata request and response fact: Chroma 0x160084 requests kind 185;
// 0x160e98 reads payload field 3 (varint or a message with varint field 1).
static const uint64_t kPlayCountExtension = 185;
static NSString *const kBase62 = @"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";

static BOOL validURI(NSString *uri, NSString *kind) {
    if (![uri isKindOfClass:NSString.class]) return NO;
    NSString *prefix = [NSString stringWithFormat:@"spotify:%@:", kind];
    if (![uri hasPrefix:prefix] || uri.length != prefix.length + 22) return NO;
    for (NSUInteger i = prefix.length; i < uri.length; i++) {
        if ([kBase62 rangeOfString:[uri substringWithRange:NSMakeRange(i, 1)]].location == NSNotFound) return NO;
    }
    return YES;
}

NSString *SGRAlbumMetadataPath(NSString *albumURI) {
    if (!validURI(albumURI, @"album")) return nil;
    NSString *identifier = [albumURI substringFromIndex:@"spotify:album:".length];
    uint8_t gid[16] = {0};
    for (NSUInteger i = 0; i < identifier.length; i++) {
        NSUInteger carry = [kBase62 rangeOfString:[identifier substringWithRange:NSMakeRange(i, 1)]].location;
        for (NSInteger j = sizeof(gid) - 1; j >= 0; j--) {
            carry += gid[j] * 62;
            gid[j] = carry & 255;
            carry >>= 8;
        }
        if (carry) return nil; // A 22-digit base62 value need not fit Spotify's 128-bit GID.
    }
    NSMutableString *hex = [NSMutableString string];
    for (NSUInteger i = 0; i < sizeof(gid); i++) [hex appendFormat:@"%02x", gid[i]];
    return [NSString stringWithFormat:@"/metadata/4/album/%@?market=from_token", hex];
}

static NSString *trackFromGID(id hex) {
    if (![hex isKindOfClass:NSString.class] || [hex length] != 32 ||
        [hex rangeOfString:@"^[0-9A-Fa-f]{32}$" options:NSRegularExpressionSearch].location == NSNotFound) return nil;
    uint8_t bytes[16];
    for (NSUInteger i = 0; i < sizeof(bytes); i++) {
        unsigned int value = 0;
        [[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i * 2, 2)]] scanHexInt:&value];
        bytes[i] = value;
    }
    unichar identifier[22];
    for (NSInteger digit = 21; digit >= 0; digit--) {
        NSUInteger remainder = 0;
        for (NSUInteger i = 0; i < sizeof(bytes); i++) {
            NSUInteger value = remainder * 256 + bytes[i];
            bytes[i] = value / 62;
            remainder = value % 62;
        }
        identifier[digit] = [kBase62 characterAtIndex:remainder];
    }
    return [@"spotify:track:" stringByAppendingString:[NSString stringWithCharacters:identifier length:22]];
}

NSString *SGRAlbumTrackURIFromMenuIdentifier(NSString *identifier) {
    NSString *prefix = @"Components.UI.ContextMenuButton-";
    if (![identifier hasPrefix:prefix]) return nil;
    NSString *uri = [@"spotify:track:" stringByAppendingString:[identifier substringFromIndex:prefix.length]];
    return validURI(uri, @"track") ? uri : nil;
}

NSArray<NSString *> *SGRAlbumMetadataTracks(NSData *json) {
    if (!json.length || json.length > kMaxCacheBytes) return nil;
    id album = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
    if (![album isKindOfClass:NSDictionary.class] || ![album[@"disc"] isKindOfClass:NSArray.class]) return nil;
    NSMutableOrderedSet *tracks = [NSMutableOrderedSet orderedSet];
    for (id disc in album[@"disc"]) {
        if (![disc isKindOfClass:NSDictionary.class] || ![disc[@"track"] isKindOfClass:NSArray.class]) return nil;
        for (id track in disc[@"track"]) {
            if (![track isKindOfClass:NSDictionary.class]) return nil;
            NSString *uri = track[@"uri"], *gidURI = trackFromGID(track[@"gid"]);
            if (!validURI(uri, @"track")) uri = gidURI;
            if (!uri || (gidURI && ![uri isEqual:gidURI])) return nil;
            [tracks addObject:uri];
            if (tracks.count > kMaxTracksPerAlbum) return nil;
        }
    }
    return tracks.count ? tracks.array : nil;
}

// Preflight without allocating a field object for each attacker-controlled tag. The common parser
// remains the codec authority; this scanner only bounds its allocation and skips wire payloads.
static BOOL skipVarint(const uint8_t *bytes, NSUInteger length, NSUInteger *at, uint64_t *value) {
    *value = 0;
    for (NSUInteger shift = 0; shift < 64 && *at < length; shift += 7) {
        uint8_t byte = bytes[(*at)++];
        if (shift == 63 && (byte & 0xfe)) return NO;
        *value |= (uint64_t)(byte & 127) << shift;
        if (!(byte & 128)) return YES;
    }
    return NO;
}

static const NSUInteger kMaxEnvelopeFields = 16, kMaxReplyDepth = 5;
static NSArray *limitedMessage(NSData *data, NSUInteger depth, NSUInteger fieldsLimit) {
    if (!data || depth > kMaxReplyDepth) return nil;
    const uint8_t *bytes = data.bytes;
    NSUInteger at = 0, fields = 0;
    while (at < data.length) {
        if (++fields > fieldsLimit) return nil;
        uint64_t tag, size;
        if (!skipVarint(bytes, data.length, &at, &tag) || !(tag >> 3)) return nil;
        switch (tag & 7) {
            case 0:
                if (!skipVarint(bytes, data.length, &at, &size)) return nil;
                continue;
            case 1: size = 8; break;
            case 5: size = 4; break;
            case 2:
                if (!skipVarint(bytes, data.length, &at, &size)) return nil;
                break;
            default: return nil;
        }
        if (size > data.length - at) return nil;
        at += (NSUInteger)size;
    }
    return SGPBParse(data);
}

static NSArray *message(NSArray *fields, uint32_t number, NSUInteger depth) {
    SGPBField *field = SGPBFirst(fields, number);
    return field.wire == 2 ? limitedMessage(field.payload, depth, kMaxEnvelopeFields) : nil;
}

NSDictionary<NSString *, NSNumber *> *SGRAlbumCountsInReply(NSData *data, NSArray<NSString *> *tracks) {
    if (!data.length || data.length > SGSpotifyMetadataMaxResponseBytes || tracks.count > kMaxTracksPerAlbum) return nil;
    NSArray *root = limitedMessage(data, 0, kMaxEnvelopeFields);
    if (!root) return nil;
    NSSet *wanted = [NSSet setWithArray:tracks];
    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    NSUInteger entries = 0;
    BOOL countExtension = NO;
    for (SGPBField *arrayField in root) {
        if (arrayField.number != 2) continue;
        if (arrayField.wire != 2) return nil;
        NSArray *array = limitedMessage(arrayField.payload, 1, kMaxTracksPerAlbum + kMaxEnvelopeFields);
        if (!array) return nil;
        for (SGPBField *field in array) {
            // Two requested extensions, at most one entry of each for every album track.
            if (field.number == 3 && ++entries > 2 * kMaxTracksPerAlbum) return nil;
        }
        SGPBField *kind = SGPBFirst(array, 2);
        if (!kind || kind.wire != 0 || kind.varint != kPlayCountExtension) continue;
        countExtension = YES;
        if (SGPBFirst(array, 1) && !message(array, 1, 2)) return nil;
        SGPBField *providerStatus = SGPBFirst(message(array, 1, 2), 1);
        if (providerStatus && (providerStatus.wire != 0 || providerStatus.varint != 200)) return nil;
        for (SGPBField *entryField in array) {
            if (entryField.number != 3) continue;
            if (entryField.wire != 2) return nil;
            NSArray *entry = limitedMessage(entryField.payload, 2, kMaxEnvelopeFields);
            if (!entry) return nil;
            NSString *uri = SGPBText(SGPBFirst(entry, 2));
            if (![wanted containsObject:uri ?: @""]) continue;
            SGPBField *status = SGPBFirst(message(entry, 1, 3), 1);
            if (!status || status.wire != 0 || status.varint != 200) return nil;
            NSArray *any = message(entry, 3, 3);
            if (!any) return nil;
            SGPBField *value = SGPBFirst(any, 2);
            if (!value || value.wire != 2) continue;
            NSArray *payload = limitedMessage(value.payload, 4, kMaxEnvelopeFields);
            if (!payload) return nil;
            SGPBField *count = SGPBFirst(payload, 3);
            if (count && count.wire == 2) {
                NSArray *wrapped = limitedMessage(count.payload, 5, kMaxEnvelopeFields);
                if (!wrapped) return nil;
                count = SGPBFirst(wrapped, 1);
            }
            // This schema has exactly one optional scalar wrapper: never descend into another.
            if (count && count.wire != 0) return nil;
            NSNumber *number = count && count.wire == 0 && count.varint <= LLONG_MAX ? @(count.varint) : nil;
            if (number) {
                if (counts[uri] && ![counts[uri] isEqual:number]) return nil;
                counts[uri] = number;
            }
#if DEBUG || SG_DRIVER
            NSLog(@"[spotifyglass] album counts: %@ kind=185 type=%@ field=%@ decoded=%@",
                  uri, SGPBText(SGPBFirst(any, 1)), SGPBFirst(payload, 3).wire == 2 ? @"3.1" : @"3", number ?: @"unavailable");
#endif
        }
    }
    return countExtension ? counts : nil;
}

static BOOL validCounts(id counts) {
    if (![counts isKindOfClass:NSDictionary.class] || [counts count] > kMaxTracksPerAlbum) return NO;
    for (id uri in counts) {
        id number = counts[uri];
        if (!validURI(uri, @"track") || ![number isKindOfClass:NSNumber.class] ||
            CFGetTypeID((__bridge CFTypeRef)number) == CFBooleanGetTypeID() ||
            [number doubleValue] < 0 || [number unsignedLongLongValue] > (unsigned long long)LLONG_MAX ||
            floor([number doubleValue]) != [number doubleValue]) return NO;
    }
    return YES;
}

@implementation SGRAlbumCountsStore {
    NSURL *_url;
    SGRAlbumCountsTransport _transport;
    dispatch_queue_t _queue;
    NSMutableDictionary *_records, *_pending;
}
- (instancetype)initWithCacheURL:(NSURL *)url transport:(SGRAlbumCountsTransport)transport {
    if (!(self = [super init])) return nil;
    _url = url;
    _transport = [transport copy];
    _queue = dispatch_queue_create("vitrine.album-counts", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    _pending = [NSMutableDictionary dictionary];
    return self;
}
- (void)readCache {
    if (_records) return;
    _records = [NSMutableDictionary dictionary];
    NSNumber *size;
    [_url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    if (!size || size.unsignedLongLongValue > kMaxCacheBytes) return;
    NSData *data = [NSData dataWithContentsOfURL:_url];
    id records = data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:nil] : nil;
    if (![records isKindOfClass:NSDictionary.class] || [records count] > kMaxCachedAlbums) return;
    for (NSString *uri in records) {
        id record = records[uri];
        if (!SGRAlbumMetadataPath(uri) || ![record isKindOfClass:NSDictionary.class] ||
            ![record[@"expires"] isKindOfClass:NSDate.class] || ![record[@"saved"] isKindOfClass:NSDate.class] ||
            !validCounts(record[@"counts"])) continue;
        if ([record[@"expires"] timeIntervalSinceNow] > 0) _records[uri] = record;
    }
}
- (void)finishAlbum:(NSString *)uri counts:(NSDictionary *)counts {
    NSDate *now = NSDate.date;
    _records[uri] = @{@"counts": counts ?: @{}, @"saved": now,
        @"expires": [now dateByAddingTimeInterval:counts ? kCountLifetimeSeconds : kUnavailableLifetimeSeconds]};
    NSArray *oldest = [_records keysSortedByValueUsingComparator:^NSComparisonResult(id a, id b) {
        return [a[@"saved"] compare:b[@"saved"]];
    }];
    NSData *data;
    NSUInteger index = 0;
    do {
        if (_records.count <= kMaxCachedAlbums)
            data = [NSPropertyListSerialization dataWithPropertyList:_records format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        if (data && data.length <= kMaxCacheBytes) break;
        [_records removeObjectForKey:oldest[index++]];
    } while (_records.count);
    NSError *error;
    BOOL directory = [NSFileManager.defaultManager createDirectoryAtURL:_url.URLByDeletingLastPathComponent
                                          withIntermediateDirectories:YES attributes:nil error:&error];
    if (!directory || ![data writeToURL:_url options:NSDataWritingAtomic error:&error])
        NSLog(@"[spotifyglass] album counts: cache write failed: %@", error.localizedDescription);
    NSArray *waiters = [_pending[uri] copy];
    [_pending removeObjectForKey:uri];
    dispatch_async(dispatch_get_main_queue(), ^{
        for (SGRAlbumCountsReply done in waiters) done(counts);
    });
}
- (void)loadAlbum:(NSString *)uri completion:(SGRAlbumCountsReply)done {
    NSString *path = SGRAlbumMetadataPath(uri);
    if (!path) { done(nil); return; }
    dispatch_async(_queue, ^{
        [self readCache];
        NSDictionary *record = self->_records[uri];
        if ([record[@"expires"] timeIntervalSinceNow] > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(record[@"counts"]); });
            return;
        }
        NSMutableArray *waiters = self->_pending[uri];
        if (waiters) {
            if (waiters.count < kMaxAlbumWaiters) [waiters addObject:[done copy]];
            else dispatch_async(dispatch_get_main_queue(), ^{ done(nil); });
            return;
        }
        if (self->_pending.count >= kMaxPendingAlbums) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil); });
            return;
        }
        self->_pending[uri] = [NSMutableArray arrayWithObject:[done copy]];
        self->_transport(path, nil, ^(NSData *json, NSInteger status, NSError *error) {
            dispatch_async(self->_queue, ^{
                NSArray *tracks = status == 200 && !error ? SGRAlbumMetadataTracks(json) : nil;
                if (!tracks) { [self finishAlbum:uri counts:nil]; return; }
                // TRACK_V4 alongside count metadata is the established request shape; titles are never read.
                NSData *body = SGSpotifyExtensionRequest(tracks, @[@10, @(kPlayCountExtension)]);
                self->_transport(SGSpotifyExtendedMetadataPath, body, ^(NSData *reply, NSInteger result, NSError *failure) {
                    dispatch_async(self->_queue, ^{
                        NSDictionary *counts = result == 200 && !failure ? SGRAlbumCountsInReply(reply, tracks) : nil;
                        [self finishAlbum:uri counts:counts];
                    });
                });
            });
        });
    });
}
@end

SGRAlbumCountsStore *SGRAlbumSpotifyCountsStore(void) {
    static SGRAlbumCountsStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
        store = [[SGRAlbumCountsStore alloc] initWithCacheURL:[base URLByAppendingPathComponent:@"Vitrine/AlbumCounts.plist"]
            transport:^(NSString *path, NSData *body, SGSpotifyMetadataReply done) { SGSpotifyMetadataRequest(path, body, done); }];
    });
    return store;
}

@implementation SGRAlbumCountPage {
    SGRAlbumCountsStore *_store;
    NSUInteger _generation;
}
- (instancetype)initWithStore:(SGRAlbumCountsStore *)store {
    if (!(self = [super init])) return nil;
    _store = store;
    return self;
}
- (void)followAlbum:(NSString *)uri changed:(dispatch_block_t)changed {
    if ([_albumURI isEqual:uri] || (!_albumURI && !uri)) return;
    _albumURI = [uri copy];
    _counts = nil;
    NSUInteger generation = ++_generation;
    changed();
    if (!SGRAlbumMetadataPath(uri)) return;
    __weak SGRAlbumCountPage *weakSelf = self;
    [_store loadAlbum:uri completion:^(NSDictionary *counts) {
        SGRAlbumCountPage *page = weakSelf;
        if (!page || page->_generation != generation) return;
        page->_counts = [counts copy];
        changed();
    }];
}
@end
