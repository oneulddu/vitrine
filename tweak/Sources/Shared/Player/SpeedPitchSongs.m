#import "SpeedPitchSongs.h"
#import "SpeedPitch.h"
#import "SpeedPitchEvents.h"
#import <CommonCrypto/CommonDigest.h>
#import <math.h>

NSNotificationName const SGSpeedPitchSongDidChange = @"spotifyglass.speedPitch.songDidChange";
static const NSUInteger kMaximumSongs = 200;
static const NSTimeInterval kWriteDelaySeconds = 0.5;

NSString *SGSpeedPitchSongIdentifier(NSString *uri) {
    if (![uri isKindOfClass:NSString.class] || !uri.length) return nil;
    if (![uri hasPrefix:@"spotify:local:"]) return uri;
    // Spotify's local URI carries form-encoded artist, album, title and duration, not a sandbox path.
    // Decode each field separately so encoded colons cannot change field boundaries.
    NSArray *parts = [uri componentsSeparatedByString:@":"];
    if (parts.count != 6) return nil;
    NSMutableArray *fields = [NSMutableArray array];
    for (NSUInteger i = 2; i < parts.count; i++) {
        NSString *field = [[parts[i] stringByReplacingOccurrencesOfString:@"+" withString:@" "]
            stringByRemovingPercentEncoding];
        if (!field) return nil;
        [fields addObject:field.precomposedStringWithCanonicalMapping];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:fields options:0 error:NULL];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *key = [NSMutableString stringWithString:@"local:"];
    // 128 bits of SHA-256, stable across launches and form-encoding variants.
    for (NSUInteger i = 0; i < 16; i++) [key appendFormat:@"%02x", digest[i]];
    return key;
}

static BOOL validValues(id record, BOOL partial) {
    if (![record isKindOfClass:NSDictionary.class]) return NO;
    NSUInteger controls = 0;
    for (NSString *key in @[@"speed", @"pitch", @"follows", @"reverb"]) {
        id value = record[key];
        if (!value && partial) continue;
        if (![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue])) return NO;
        ++controls;
    }
    if (!controls || (partial && controls != [record count])) return NO;
    return (!record[@"speed"] || ([record[@"speed"] doubleValue] >= 0.5 && [record[@"speed"] doubleValue] <= 2))
        && (!record[@"pitch"] || fabs([record[@"pitch"] doubleValue]) <= 12)
        && (!record[@"follows"] || [record[@"follows"] doubleValue] == 0 || [record[@"follows"] doubleValue] == 1)
        && (!record[@"reverb"] || ([record[@"reverb"] doubleValue] >= 0 && [record[@"reverb"] doubleValue] <= 100));
}

static BOOL validRecord(id record) {
    return validValues(record, NO) && [record[@"timestamp"] isKindOfClass:NSNumber.class]
        && isfinite([record[@"timestamp"] doubleValue]);
}

@implementation SGSpeedPitchSongs {
    NSUserDefaults *_defaults;
    NSMutableDictionary<NSString *, NSDictionary *> *_records;
    NSString *_song;
    NSDictionary *_before;
    NSNumber *_pendingSpeed, *_pendingPitch;
    NSUInteger _generation;
    BOOL _applying, _dirty, _reported, _restoring;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    if (!(self = [super init])) return nil;
    _defaults = defaults;
    _records = [NSMutableDictionary dictionary];
    id stored = [defaults objectForKey:SGKeySpeedPitchSongs];
    if ([stored isKindOfClass:NSDictionary.class]) {
        for (id key in stored) {
            if ([key isKindOfClass:NSString.class] && [key length] && validRecord(stored[key]))
                _records[key] = stored[key];
        }
    }
    [self trim];
    id baseline = [defaults objectForKey:SGKeySpeedPitchBaseline];
    if (validValues(baseline, YES)) _before = [baseline copy];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reverbChanged:)
        name:SGSpeedPitchReverbDidChange object:nil];
    return self;
}

- (void)reverbChanged:(NSNotification *)notification {
    [self valuesChanged:@"reverb"];
}

- (BOOL)hasSong { return _song != nil; }
- (BOOL)kept { return _song && _records[_song] != nil; }

- (NSDictionary *)values {
    return @{@"speed": _pendingSpeed ?: @(SGPlayerSpeed()),
             @"pitch": _pendingPitch ?: @(SGPlayerPitch()),
             @"follows": @(SGPlayerPitchFollowsSpeed()), @"reverb": @(SGPlayerReverb())};
}

- (void)storeBaseline:(NSDictionary *)baseline {
    if ([_before isEqual:baseline] || (!_before && !baseline.count)) return;
    _before = baseline.count ? [baseline copy] : nil;
    if (_before) [_defaults setObject:_before forKey:SGKeySpeedPitchBaseline];
    else [_defaults removeObjectForKey:SGKeySpeedPitchBaseline];
}

- (void)saveBaseline {
    // A partial restore may be interrupted by another kept song. Preserve the still-outstanding
    // controls and capture the current values of the others before the new record overwrites them.
    NSMutableDictionary *baseline = [[self values] mutableCopy];
    if (_before) [baseline addEntriesFromDictionary:_before];
    [self storeBaseline:baseline];
}

- (void)finishRestoring {
    if (!_restoring) return;
    NSMutableDictionary *remaining = [_before mutableCopy];
    // Reverb and pitch-follow restore synchronously. Keep only controls still waiting for admission.
    [remaining removeObjectForKey:@"reverb"];
    [remaining removeObjectForKey:@"follows"];
    if (!_pendingSpeed) [remaining removeObjectForKey:@"speed"];
    if (!_pendingPitch) [remaining removeObjectForKey:@"pitch"];
    [self storeBaseline:remaining];
    _restoring = _before != nil;
}

- (void)applyPending {
    _applying = YES;
    if (_pendingSpeed && SGPlayerSpeedAllowed()) {
        SGSetPlayerSpeed(_pendingSpeed.doubleValue);
        _pendingSpeed = nil;
    }
    if (_pendingPitch && SGPlayerPitchAvailable()) {
        SGSetPlayerPitch(_pendingPitch.floatValue);
        _pendingPitch = nil;
    }
    _applying = NO;
    [self finishRestoring];
}

- (void)applyValues:(NSDictionary *)values {
    _applying = YES;
    _pendingSpeed = values[@"speed"];
    _pendingPitch = values[@"pitch"];
    // Keep admission and DSP topology in their existing owners. Only control-side setters run here.
    if (values[@"follows"]) SGSetPlayerPitchFollowsSpeed([values[@"follows"] boolValue]);
    if (values[@"reverb"]) SGPlayerSetReverb([values[@"reverb"] floatValue]);
    [self applyPending];
    _applying = NO;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {}
- (void)playerStateDidReport:(SPTPlayerState *)state {
    if (!state) return; // Startup may run before the first actual player report.
    NSString *song = SGSpeedPitchSongIdentifier(SGURIString(state.track.URI));
    if (!_reported || (![_song isEqualToString:song] && (_song || song))) {
        _reported = YES;
        [self flush]; // Do not lose the last slider movement on a skip.
        _song = song;
        NSDictionary *record = song ? _records[song] : nil;
        if (record) {
            _restoring = NO;
            [self saveBaseline];
            [self applyValues:record];
        } else if (_before) {
            _restoring = YES;
            [self applyValues:_before];
        }
        [NSNotificationCenter.defaultCenter postNotificationName:SGSpeedPitchSongDidChange object:self];
    }
    // A track may be reported before Spotify admits an output. Retry only the unavailable controls
    // on subsequent main-thread reports; never rewrite the saved record with the unapplied values.
    [self applyPending];
}

- (void)trim {
    while (_records.count > kMaximumSongs) {
        NSString *oldest = [[_records allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            NSComparisonResult order = [_records[a][@"timestamp"] compare:_records[b][@"timestamp"]];
            return order == NSOrderedSame ? [a compare:b] : order;
        }].firstObject;
        [_records removeObjectForKey:oldest];
    }
}

- (void)recordValues {
    NSMutableDictionary *record = [[self values] mutableCopy];
    record[@"timestamp"] = @(NSDate.date.timeIntervalSince1970);
    _records[_song] = record;
    [self trim];
    _dirty = YES;
}

- (void)flush {
    ++_generation;
    if (!_dirty) return;
    [_defaults setObject:[_records copy] forKey:SGKeySpeedPitchSongs];
    _dirty = NO;
}

- (void)setKept:(BOOL)kept {
    if (!self.hasSong || kept == self.kept) return;
    if (kept) {
        _restoring = NO;
        [self saveBaseline];
        [self recordValues];
    } else {
        [_records removeObjectForKey:_song];
        _dirty = YES;
        if (_before) {
            _restoring = YES;
            [self applyValues:_before];
        }
    }
    [self flush];
    [NSNotificationCenter.defaultCenter postNotificationName:SGSpeedPitchSongDidChange object:self];
}

- (void)valuesChanged:(NSString *)control {
    if (_applying) return;
    // A successful user setter supersedes a value waiting for an output.
    if ([control isEqualToString:@"speed"]) _pendingSpeed = nil;
    if ([control isEqualToString:@"pitch"]) _pendingPitch = nil;
    if (!self.kept && control && _before[control]) {
        NSMutableDictionary *remaining = [_before mutableCopy];
        [remaining removeObjectForKey:control];
        [self storeBaseline:remaining];
    }
    [self finishRestoring];
    if (!self.kept) return;
    NSMutableDictionary *saved = [_records[_song] mutableCopy];
    [saved removeObjectForKey:@"timestamp"];
    if ([saved isEqual:[self values]]) return;
    [self recordValues];
    NSUInteger generation = ++_generation;
    __weak SGSpeedPitchSongs *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kWriteDelaySeconds * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            SGSpeedPitchSongs *owner = weakSelf;
            if (owner && owner->_generation == generation) [owner flush];
        });
}
@end

static SGSpeedPitchSongs *sg_songs;
void SGSpeedPitchSongsStart(void) {
    if (sg_songs) return;
    sg_songs = [[SGSpeedPitchSongs alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
    SGAddPlayerStateObserver(sg_songs);
    [sg_songs playerStateDidReport:SGPlayerState()];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification
        object:nil queue:nil usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{ [sg_songs flush]; });
        }];
}
BOOL SGPlayerSongCanKeep(void) { return sg_songs.hasSong; }
BOOL SGPlayerSongKept(void) { return sg_songs.kept; }
void SGPlayerSongSetKept(BOOL kept) { [sg_songs setKept:kept]; }
void SGSpeedPitchSongValuesChanged(NSString *control) { [sg_songs valuesChanged:control]; }
