// The chain: sources asked in order or all at once, with timed lyrics answering promptly.
//
// Stopping at the first answer is what makes the lyrics card under the player appear at all. For a
// track Spotify has no lyrics of its own for, the card is only offered when the answer to Spotify's
// lyrics request arrives within about a second of the player building its list of cards; a walk that
// went on through every source for word timing took three seconds and more, and the card never came.
// Word timing first (the default) answers just as soon, then keeps looking for finer timing,
// keeping source priority for ties. All at once keeps the first word-timed answer to arrive.
#import "Core/SGCore.h"
#import "LyricsSources.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LocalFiles/LocalFiles.h"
#import "Shared/LocalFiles/LocalLyrics.h"
#import "Settings/SGSourcesPage.h"
#import "Settings/SGPageStyle.h"
#import "Headers/SPTPlayer.h"
#import <stdatomic.h>

static const NSTimeInterval kTimeout = 6;
static const NSUInteger kKeptTracks = 40;

// What the switches were called while Musixmatch was the only source; read once, to carry an
// existing install's settings over to the order.
static NSString *const kLegacyMusixmatch = @"spotifyglass.musixmatchLyrics";
static NSString *const kLegacyAllTracks = @"spotifyglass.musixmatchAllTracks";
static NSString *const kLegacyNetEase = @"spotifyglass.neteaseWordTiming";

@implementation SGLyricsLink
@end

@implementation SGLyricsResult
@end

@implementation SGLyricsQuery
@end

@implementation SGLyricsProvider
@end

#pragma mark - the requests the sources share

// Every request any source has lost to the network or to a server too busy to answer, counted so a
// walk can tell "no source has lyrics" from "a source could not say". Only the first is kept.
static _Atomic NSUInteger sg_failures;

BOOL SGLyricsReplyFailed(NSURLResponse *response, NSError *error) {
    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    return error || status == 429 || status >= 500;
}

void SGLyricsNoteReply(NSURLResponse *response, NSError *error) {
    if (SGLyricsReplyFailed(response, error)) atomic_fetch_add(&sg_failures, 1);
}

NSURL *SGLyricsURL(NSString *base, NSDictionary<NSString *, NSString *> *query) {
    NSURLComponents *url = [NSURLComponents componentsWithString:base];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    [query enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [items addObject:[NSURLQueryItem queryItemWithName:name value:value]];
    }];
    url.queryItems = items;
    return url.URL;
}

static NSMutableURLRequest *requestFor(NSURL *url, NSDictionary<NSString *, NSString *> *headers) {
    if (!url) return nil;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:kTimeout];
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [request setValue:value forHTTPHeaderField:name];
    }];
    return request;
}

// The body whatever the status, and the reply it came with; nil for both when there was none.
static void sendForReply(NSURLRequest *request, void (^done)(NSData *body, NSHTTPURLResponse *response)) {
    if (!request) {
        dispatch_async(dispatch_get_main_queue(), ^{ done(nil, nil); });
        return;
    }
    NSURL *url = request.URL;
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *reply = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        SGLyricsNoteReply(response, error);
        if (error || reply.statusCode >= 400) SGLog(@"lyrics: %@ answered %ld, error %@", url.host, (long)reply.statusCode, error);
        dispatch_async(dispatch_get_main_queue(), ^{ done(data, reply); });
    }] resume];
}

static void send(NSURLRequest *request, void (^done)(NSData *body)) {
    sendForReply(request, ^(NSData *body, NSHTTPURLResponse *reply) {
        done(reply.statusCode >= 400 ? nil : body);
    });
}

static id jsonIn(NSData *body) {
    return body.length ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : nil;
}

void SGLyricsGetJSON(NSURL *url, NSDictionary<NSString *, NSString *> *headers, void (^done)(id root)) {
    send(requestFor(url, headers), ^(NSData *body) {
        done(jsonIn(body));
    });
}

void SGLyricsGetJSONReply(NSURL *url, NSDictionary<NSString *, NSString *> *headers, void (^done)(id root, NSHTTPURLResponse *response)) {
    sendForReply(requestFor(url, headers), ^(NSData *body, NSHTTPURLResponse *reply) {
        done(jsonIn(body), reply);
    });
}

void SGLyricsGetText(NSURL *url, void (^done)(NSString *text)) {
    send(requestFor(url, nil), ^(NSData *body) {
        done(body.length ? [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding] : nil);
    });
}

void SGLyricsPostJSON(NSURL *url, NSDictionary<NSString *, NSString *> *headers, id body, void (^done)(id root)) {
    NSData *written = [NSJSONSerialization isValidJSONObject:body]
        ? [NSJSONSerialization dataWithJSONObject:body options:0 error:nil] : nil;
    NSMutableURLRequest *request = written ? requestFor(url, headers) : nil;
    request.HTTPMethod = @"POST";
    request.HTTPBody = written;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    send(request, ^(NSData *answer) {
        done(jsonIn(answer));
    });
}

// A private session keeps a login cookie out of the shared cookie jar and disk cache. Receiving
// chunks lets us stop a broken endpoint before its reply grows into an unbounded allocation.
@interface SGLyricsSourceTransfer : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSMutableData *data;
@property (nonatomic, copy) void (^done)(NSData *, NSInteger);
@property (nonatomic) NSInteger status;
@end
@implementation SGLyricsSourceTransfer
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
 didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {
    self.status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    SGLyricsNoteReply(response, nil);
    completion(response.expectedContentLength > 2 * 1024 * 1024 ? NSURLSessionResponseCancel : NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (data.length > 2 * 1024 * 1024 - self.data.length) { [task cancel]; return; }
    [self.data appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
 willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completion { completion(nil); }
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) SGLyricsNoteReply(nil, error);
    if (error || self.status >= 400) SGLog(@"lyrics: source request ended with HTTP %ld, error %ld", (long)self.status, (long)error.code);
    NSData *data = error ? nil : [self.data copy];
    void (^done)(NSData *, NSInteger) = self.done;
    self.done = nil;
    if (done) done(data, self.status);
    [session finishTasksAndInvalidate];
}
@end

void SGLyricsSourceRequest(NSURL *url, NSDictionary<NSString *, NSString *> *headers, NSData *body,
                           void (^done)(NSData *, NSInteger)) {
    NSMutableURLRequest *request = requestFor(url, headers);
    if (!request || ![url.scheme isEqualToString:@"https"]) {
        dispatch_async(dispatch_get_main_queue(), ^{ done(nil, 0); });
        return;
    }
    request.HTTPShouldHandleCookies = NO;
    if (body) { request.HTTPMethod = @"POST"; request.HTTPBody = body; }
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.HTTPCookieStorage = nil;
    config.URLCredentialStorage = nil;
    config.URLCache = nil;
    config.timeoutIntervalForResource = kTimeout;
    SGLyricsSourceTransfer *transfer = [SGLyricsSourceTransfer new];
    transfer.data = [NSMutableData data];
    transfer.done = done;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:transfer delegateQueue:NSOperationQueue.mainQueue];
    [[session dataTaskWithRequest:request] resume];
}

// A pause this long between two lines gets a ♪, so Spotify's page does not hold the last one.
static const NSInteger kBreakMs = 3000;

void SGLyricsPageLines(NSArray<SGKaraokeLine *> *lines, NSArray<NSNumber *> **starts, NSArray<NSString *> **texts) {
    NSMutableArray<NSNumber *> *at = [NSMutableArray array];
    NSMutableArray<NSString *> *said = [NSMutableArray array];
    SGKaraokeLine *last = nil;
    for (SGKaraokeLine *line in lines) {
        if (last && line.start - last.end >= kBreakMs) {
            [at addObject:@(last.end)];
            [said addObject:@"♪"];
        }
        NSString *text = SGKaraokeLineText(line);
        // The backing vocals read on the same line on Spotify's own page, which has one row a line.
        if (line.backing) text = [text stringByAppendingFormat:@" %@", SGKaraokeLineText(line.backing)];
        [at addObject:@(line.start)];
        [said addObject:text];
        last = line;
    }
    if (last) {
        [at addObject:@(last.end)];
        [said addObject:@""];
    }
    *starts = at;
    *texts = said;
}

#pragma mark - which sources there are, and in what order

NSArray<SGLyricsProvider *> *SGLyricsAllProviders(void) {
    static NSArray<SGLyricsProvider *> *all;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGLyricsProvider *(^make)(NSString *, NSString *, NSString *, SGLyricsAsk) =
        ^(NSString *key, NSString *name, NSString *detail, SGLyricsAsk ask) {
            SGLyricsProvider *provider = [SGLyricsProvider new];
            provider.key = key;
            provider.name = name;
            provider.detail = detail;
            // A source that matches by Spotify's own track id has everything it needs from the
            // start; the rest wait for the player to name the track before they can search.
            provider.needsName = ![key isEqualToString:@"musixmatch"] && ![key isEqualToString:SGSpicyLyricsKey];
            provider.untimed = [key isEqualToString:@"genius"];
            provider.ask = ask;
            return provider;
        };
        all = @[
            make(@"binilyrics", @"BiniLyrics", SGL(@"settings.lyricssources.binilyrics.subtitle", @"Apple Music word timing"), SGBiniLyricsAsk),
            make(@"lyricsplus", @"LyricsPlus", SGL(@"settings.lyricssources.lyricsplus.subtitle", @"Word and line timing, multiple catalogs"), SGLyricsPlusAsk),
            make(@"musixmatch", @"Musixmatch", SGL(@"settings.lyricssources.musixmatch.subtitle", @"Spotify's licensed catalog"), SGMusixmatchAsk),
            make(@"unison", @"Unison", SGL(@"settings.lyricssources.unison.subtitle", @"Hand-timed, few tracks"), SGUnisonAsk),
            make(@"netease", @"NetEase", SGL(@"settings.lyricssources.netease.subtitle", @"Word timing, censored"), SGNetEaseAsk),
            make(@"lrclib", @"LRCLIB", SGL(@"settings.lyricssources.lrclib.subtitle", @"Line timing, open fallback"), SGLrcLibAsk),
            make(@"bugs", @"Bugs", SGL(@"settings.lyricssources.bugs.subtitle", @"Line timing, Korean catalog"), SGBugsAsk),
            make(@"genie", @"Genie", SGL(@"settings.lyricssources.genie.subtitle", @"Line timing, Korean catalog"), SGGenieAsk),
            make(SGSpicyLyricsKey, @"Spicy Lyrics", SGL(@"settings.lyricssources.spicylyrics.subtitle", @"Community word syncs, your own key"), SGSpicyLyricsAsk),
            make(@"qqmusic", @"QQ Music", SGL(@"settings.lyricssources.qqmusic.subtitle", @"Line timing, Chinese catalog"), SGQQMusicAsk),
            make(@"kugou", @"KuGou", SGL(@"settings.lyricssources.kugou.subtitle", @"Word timing, Chinese catalog"), SGKuGouAsk),
            make(@"deezer", @"Deezer", SGL(@"settings.lyricssources.deezer.subtitle", @"Word and line timing, your own ARL"), SGDeezerAsk),
            make(SGImportedLRCKey, SGL(@"settings.lyricssources.importedlrc.title", @"Imported LRC"), SGL(@"settings.lyricssources.importedlrc.subtitle", @"Your own .lrc files"), SGImportedLRCAsk),
            make(@"genius", @"Genius", SGL(@"settings.lyricssources.genius.subtitle", @"Untimed, when no other has lyrics"), SGGeniusAsk),
        ];
    });
    return all;
}

SGLyricsProvider *SGLyricsProviderFor(NSString *key) {
    for (SGLyricsProvider *provider in SGLyricsAllProviders()) {
        if ([provider.key isEqualToString:key]) return provider;
    }
    return nil;
}

// An install from before the order existed keeps what it had: the sources it was using, in the only
// order there was. Nothing is switched on for it that it had not already asked for.
static NSArray<NSString *> *fromLegacyKeys(void) {
    if (!SGFlag(kLegacyMusixmatch, NO)) return @[];
    NSMutableArray<NSString *> *order = [NSMutableArray arrayWithObject:@"musixmatch"];
    if (SGFlag(kLegacyNetEase, NO)) [order addObject:@"netease"];
    return order;
}

// With nothing stored and nothing to carry over, every source is on: the user's own files first,
// word timing ahead of line timing, and the two Chinese catalogs after the rest.
// Stored orders are untouched. Sources needing a key pass straight on without one.
static NSArray<NSString *> *defaultOrder(void) {
    return @[SGImportedLRCKey, SGSpicyLyricsKey, @"binilyrics", @"lyricsplus", @"musixmatch",
             @"unison", @"deezer", @"netease", @"lrclib", @"bugs", @"genie", @"qqmusic", @"kugou", @"genius"];
}

NSArray<NSString *> *SGLyricsOrder(void) {
    id stored = [NSUserDefaults.standardUserDefaults arrayForKey:SGKeyLyricsProviders];
    // A reset leaves sources off until the user saves an order, including an explicitly empty one.
    if (!stored && [NSUserDefaults.standardUserDefaults boolForKey:SGKeyStock]) return @[];
    NSArray *legacy = fromLegacyKeys();
    NSArray *keys = [stored isKindOfClass:NSArray.class] ? stored : legacy.count ? legacy : defaultOrder();
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (id key in keys) {
        if ([key isKindOfClass:NSString.class] && SGLyricsProviderFor(key) && ![order containsObject:key]) [order addObject:key];
    }
    return order;
}

void SGLyricsSetOrder(NSArray<NSString *> *keys) {
    [NSUserDefaults.standardUserDefaults setObject:keys ?: @[] forKey:SGKeyLyricsProviders];
}

// With EeveeSpotify injected, its own lyrics answer Spotify's requests and the mod's stand aside: two
// tweaks holding and answering the same request froze Spotify after launch.
BOOL SGLyricsEnabled(void) {
    return SGLyricsOrder().count > 0 && !SGLyricsStandAsideForEevee();
}

#pragma mark - what is known about the track

// The player knows every track it has played by name, which is what every source but Musixmatch
// searches by. The track is looked up by id rather than compared with the one playing now: a lyrics
// request often lands a beat before the player moves on to its track, and comparing then left the
// query nameless. A track the player has not reported starts with nothing, and the first source
// that matches by id fills the rest in.
static SGLyricsQuery *queryFor(NSString *trackID) {
    SGLyricsQuery *query = [SGLyricsQuery new];
    query.trackID = trackID;
    // A local file is named by its own key: its tags, and the names the user gave it over them.
    NSDictionary *local = SGLocalFileInfo(trackID);
    if (local) {
        query.title = local[@"title"];
        query.artist = local[@"artist"];
        query.album = local[@"album"];
        query.seconds = [local[@"seconds"] integerValue];
        return query;
    }
    SPTPlayerTrack *track = SGKaraokeTrackFor(trackID);
    if (!track) return query;
    query.title = track.trackTitle;
    query.artist = track.artistName;
    NSDictionary<NSString *, NSString *> *metadata = track.metadata;
    id album = metadata[@"album_title"];
    id length = metadata[@"duration"];
    if ([album isKindOfClass:NSString.class]) query.album = album;
    if ([length respondsToSelector:@selector(integerValue)]) query.seconds = [length integerValue] / 1000;
    return query;
}

static void learnFrom(SGLyricsQuery *query, SGLyricsResult *result) {
    if (!query.title.length && result.title.length) query.title = result.title;
    if (!query.artist.length && result.artist.length) query.artist = result.artist;
    if (!query.album.length && result.album.length) query.album = result.album;
    if (query.seconds <= 0 && result.seconds > 0) query.seconds = result.seconds;
}

#pragma mark - the walk

// Main queue only, except sg_missing and sg_credits.
static NSMutableDictionary<NSString *, id> *sg_kept;
static NSMutableDictionary<NSString *, NSMutableArray *> *sg_waiting;
static NSMutableSet<NSString *> *sg_missing;
static NSMutableDictionary<NSString *, NSNumber *> *sg_pins;
// Guarded by sg_pins; generations survive unpinning to reject old hook deliveries.
static NSMutableDictionary<NSString *, NSNumber *> *sg_pinGenerations;
NSNotificationName const SGLyricsPinDidChangeNotification = @"spotifyglass.lyrics.pinDidChange";
NSNotificationName const SGLyricsDidReloadNotification = @"spotifyglass.lyrics.didReload";
static NSMutableDictionary<NSString *, NSString *> *sg_credits;
// Spotify's own has_lyrics per track, as its metadata said. The player's metadata is read many
// times a second while a list scrolls, so a value already noted costs one lookup and no write.
static NSMutableDictionary<NSString *, NSNumber *> *sg_spotifyHas;
static const NSUInteger kNotedTracks = 200;

static void setUp(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sg_kept = [NSMutableDictionary dictionary];
        sg_waiting = [NSMutableDictionary dictionary];
        sg_missing = [NSMutableSet set];
        sg_credits = [NSMutableDictionary dictionary];
        sg_spotifyHas = [NSMutableDictionary dictionary];
        sg_pins = [NSMutableDictionary dictionary];
        sg_pinGenerations = [NSMutableDictionary dictionary];
        id stored = [NSUserDefaults.standardUserDefaults objectForKey:SGKeyLyricsPins];
        if ([stored isKindOfClass:NSDictionary.class]) {
            for (id track in stored) {
                id identifier = stored[track];
                if (sg_pins.count >= 500) break;
                if ([track isKindOfClass:NSString.class] && [track length] && [identifier isKindOfClass:NSNumber.class]
                    && SGLyricsDecimalID(identifier).length && [identifier longLongValue] > 0) sg_pins[track] = identifier;
            }
        }
    });
}

NSNumber *SGLyricsPinnedID(NSString *trackID) {
    setUp();
    @synchronized (sg_pins) { return trackID ? sg_pins[trackID] : nil; }
}

NSUInteger SGLyricsPinGeneration(NSString *trackID) {
    setUp();
    @synchronized (sg_pins) { return trackID ? sg_pinGenerations[trackID].unsignedIntegerValue : 0; }
}

static void whenNamed(NSString *trackID, NSTimeInterval waited, NSMutableArray *waiting);

BOOL SGLyricsPin(NSString *trackID, NSDictionary *record) {
    if (!trackID.length || ![record isKindOfClass:NSDictionary.class]) return NO;
    // The menu may hand back its shaped entry or the raw record it carries.
    if ([record[@"record"] isKindOfClass:NSDictionary.class]) record = record[@"record"];
    id identifier = record[@"id"];
    if (![identifier isKindOfClass:NSNumber.class] || !SGLyricsDecimalID(identifier).length || [identifier longLongValue] <= 0) return NO;
    SGLyricsResult *result = SGLrcLibRecordResult(record);
    if (!result.instrumental && !result.karaokeLines.count) return NO;
    setUp();
    @synchronized (sg_pins) {
        sg_pinGenerations[trackID] = @(sg_pinGenerations[trackID].unsignedIntegerValue + 1);
        sg_pins[trackID] = identifier;
        for (NSString *other in sg_pins.allKeys) {
            if (sg_pins.count <= 500) break;
            if (![other isEqualToString:trackID]) [sg_pins removeObjectForKey:other];
        }
        [NSUserDefaults.standardUserDefaults setObject:[sg_pins copy] forKey:SGKeyLyricsPins];
    }
    NSArray *waiting = sg_waiting[trackID];
    [sg_waiting removeObjectForKey:trackID];
    if (sg_kept.count >= kKeptTracks && !sg_kept[trackID]) [sg_kept removeAllObjects];
    sg_kept[trackID] = result;
    @synchronized (sg_missing) { [sg_missing removeObject:trackID]; }
    SGKaraokeForgetLyrics(trackID);
    SGLyricsSetCredit(trackID, @"LRCLIB");
    SGKaraokeKeepLines(trackID, result.karaokeLines ?: @[]);
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsPinDidChangeNotification object:trackID];
    for (void (^done)(SGLyricsResult *) in waiting) done(result);
    return YES;
}

static void reloadTrack(NSString *trackID, BOOL unpin) {
    if (!trackID.length) return;
    setUp();
    @synchronized (sg_pins) {
        sg_pinGenerations[trackID] = @(sg_pinGenerations[trackID].unsignedIntegerValue + 1);
        if (unpin) {
            [sg_pins removeObjectForKey:trackID];
            [NSUserDefaults.standardUserDefaults setObject:[sg_pins copy] forKey:SGKeyLyricsPins];
        }
    }
    [sg_kept removeObjectForKey:trackID];
    @synchronized (sg_missing) { [sg_missing removeObject:trackID]; }
    @synchronized (sg_credits) { [sg_credits removeObjectForKey:trackID]; }
    // A new waiter array retires the old walk while keeping everyone who still needs its answer.
    NSMutableArray *waiting = [sg_waiting[trackID] mutableCopy];
    [sg_waiting removeObjectForKey:trackID];
    SGKaraokeForgetLyrics(trackID);
    [NSNotificationCenter.defaultCenter postNotificationName:unpin ? SGLyricsPinDidChangeNotification : SGLyricsDidReloadNotification object:trackID];
    if (waiting) {
        sg_waiting[trackID] = waiting;
        whenNamed(trackID, 0, waiting);
    }
    SGKaraokeRequestLyrics(trackID);
}

void SGLyricsUnpin(NSString *trackID) { reloadTrack(trackID, YES); }
void SGLyricsReload(NSString *trackID) { reloadTrack(trackID, NO); }

// Whether the source's lines are better than what the walk already has: any lines beat none, and
// finer timing beats coarser — words timed beat a line's start, which beats plain text. Read off the
// lines themselves, which say how they were really timed, rather than off what the source claimed.
static BOOL betterLines(SGLyricsResult *merged, SGLyricsResult *fresh) {
    if (!fresh.karaokeLines.count) return NO;
    return !merged.karaokeLines.count || SGKaraokeLinesTiming(fresh.karaokeLines) < SGKaraokeLinesTiming(merged.karaokeLines);
}

static NSString *timingName(NSArray<SGKaraokeLine *> *lines) {
    switch (SGKaraokeLinesTiming(lines)) {
        case SGKaraokeTimingWords: return @"word timed";
        case SGKaraokeTimingLine: return @"line timed";
        default: return @"untimed";
    }
}

// The same for the text Spotify's own page shows: any text beats none, timed beats untimed.
static BOOL betterTexts(SGLyricsResult *merged, SGLyricsResult *fresh) {
    if (!fresh.texts.count) return NO;
    return !merged.texts.count || (fresh.synced && !merged.synced);
}

// How long a lyrics request waits for the player to name its track before the walk starts without a
// name. The request routinely lands a few hundred milliseconds before the player reports the track
// it belongs to, and a walk started in that gap passes over every source that searches by name.
static const NSTimeInterval kNameWait = 1.5, kNamePoll = 0.1;

static BOOL named(SGLyricsQuery *query) {
    return query.title.length && query.artist.length;
}

// The credits that carry links or must show, by their text, as their sources answered. Main queue.
static NSMutableDictionary<NSString *, SGLyricsResult *> *sg_noted;
static const NSUInteger kNotedCredits = 100;

static void noteCredit(SGLyricsResult *result) {
    if (!result.provider.length || !(result.creditRequired || result.creditLinks.count)) return;
    if (!sg_noted) sg_noted = [NSMutableDictionary dictionary];
    if (sg_noted.count >= kNotedCredits) [sg_noted removeAllObjects];
    sg_noted[result.provider] = result;
}

BOOL SGLyricsCreditRequired(NSString *credit) {
    return credit && sg_noted[credit].creditRequired;
}

NSArray<SGLyricsLink *> *SGLyricsCreditLinks(NSString *text) {
    if (!text.length) return nil;
    SGLyricsResult *exact = sg_noted[text];
    if (exact) return exact.creditLinks;
    // The longest credit the text holds, so "Spicy Lyrics, synced by a" is not read as a shorter one.
    SGLyricsResult *found = nil;
    for (NSString *credit in sg_noted) {
        if ([text containsString:credit] && credit.length > found.provider.length) found = sg_noted[credit];
    }
    return found.creditLinks;
}

void SGLyricsOpenCreditLinks(NSArray<SGLyricsLink *> *links, UIView *from) {
    if (!links.count) return;
    if (links.count == 1) {
        [UIApplication.sharedApplication openURL:links.firstObject.url options:@{} completionHandler:nil];
        return;
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (SGLyricsLink *link in links) {
        NSURL *url = link.url;
        [sheet addAction:[UIAlertAction actionWithTitle:link.title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = from;
    sheet.popoverPresentationController.sourceRect = from.bounds;
    [SGTopController() presentViewController:sheet animated:YES completion:nil];
}

// One walk down the order for one track.
@interface SGLyricsWalk : NSObject
@property (nonatomic, copy) NSArray<NSString *> *order;
@property (nonatomic) NSUInteger index;
@property (nonatomic) BOOL typeFirst;
@property (nonatomic) BOOL concurrent, finished, instrumental;
@property (nonatomic, strong) NSMutableSet<NSString *> *started, *inFlight;
@property (nonatomic) BOOL answered;
@property (nonatomic, copy) NSArray<NSString *> *originalOrder;
@property (nonatomic) NSUInteger lineRank, pageRank;
@property (nonatomic) SGKaraokeTiming pageTiming;
@property (nonatomic, strong) SGLyricsQuery *query;
@property (nonatomic, strong) SGLyricsResult *merged;
// The waiters this walk started for. A pin or an unpin replaces them, retiring late replies.
@property (nonatomic, strong) NSMutableArray *waiting;
// Sources that needed a name the query did not have when their turn came.
@property (nonatomic, strong) NSMutableArray<NSString *> *passedOver;
// sg_failures when the walk started. Another walk's failure counts too, which at worst asks again.
@property (nonatomic) NSUInteger failuresAtStart;
@end

@implementation SGLyricsWalk
@end

// Musixmatch's community translations are not waited for here: the lines take them as they are kept
// for the lyrics view (Shared/Lyrics/KaraokeSource.x), whichever source won, Spotify included.
static void finish(SGLyricsWalk *walk) {
    if (walk.finished || sg_waiting[walk.query.trackID] != walk.waiting) return;
    walk.finished = YES;
    SGLyricsQuery *query = walk.query;
    SGLyricsResult *merged = walk.merged;
    NSString *trackID = query.trackID;
    SGLyricsResult *lyrics = merged.karaokeLines.count || merged.texts.count || merged.instrumental ? merged : nil;
    // A walk that ends with nothing is only an answer when every source got to search. One that passed a
    // source over for want of a name asked it nothing, and keeping that as "no lyrics" would stick to the
    // track: every later request would get the kept nil, and the lyrics card would be taken off the track
    // for the rest of the session. The same goes for a walk during which a request failed: a busy
    // server's 503 read as "no lyrics" hid a track's lyrics until Spotify was restarted.
    BOOL everyoneAsked = !walk.passedOver.count;
    BOOL failed = atomic_load(&sg_failures) != walk.failuresAtStart;
    if (lyrics || (everyoneAsked && !failed) || merged.instrumental) {
        if (sg_kept.count >= kKeptTracks) [sg_kept removeAllObjects];
        sg_kept[trackID] = lyrics ?: NSNull.null;
        if (!lyrics) {
            @synchronized (sg_missing) { [sg_missing addObject:trackID]; }
        }
    }
    SGLog(@"lyrics: %@ ends with %@", trackID, lyrics
          ? [NSString stringWithFormat:@"%lu %@ lines from %@, %lu page lines",
             (unsigned long)lyrics.karaokeLines.count, timingName(lyrics.karaokeLines),
             lyrics.provider, (unsigned long)lyrics.texts.count]
          : everyoneAsked && failed ? @"nothing, a request failed on the way; not kept, so the next request asks again"
          : everyoneAsked ? @"nothing"
          : [NSString stringWithFormat:@"nothing, %@ never knowing its name; not kept, so the next request asks again",
             [walk.passedOver componentsJoinedByString:@", "]]);
    NSArray *waiting = sg_waiting[trackID];
    [sg_waiting removeObjectForKey:trackID];
    for (void (^done)(SGLyricsResult *) in waiting) done(lyrics);
}

// Both schedulers share delivery, filtering, ranking and upgrade publication.
static BOOL currentWalk(SGLyricsWalk *walk) {
    return !walk.finished && sg_waiting[walk.query.trackID] == walk.waiting;
}

static BOOL releaseAnswer(SGLyricsWalk *walk) {
    SGLyricsQuery *query = walk.query;
    SGLyricsResult *merged = walk.merged;
    if (walk.typeFirst && !walk.answered && merged.synced && merged.texts.count && merged.karaokeLines.count) {
        // Release the card request now, but keep this array as the walk's identity. A reload or
        // pin still retires it, and requests arriving meanwhile get the best answer kept so far.
        walk.answered = YES;
        if (sg_kept.count >= kKeptTracks) [sg_kept removeAllObjects];
        sg_kept[query.trackID] = merged;
        while (walk.waiting.count && sg_waiting[query.trackID] == walk.waiting) {
            void (^done)(SGLyricsResult *) = walk.waiting.firstObject;
            [walk.waiting removeObjectAtIndex:0];
            done(merged);
        }
        // A waiter may itself have pinned or reloaded the track.
        if (!currentWalk(walk)) return NO;
    }
    return currentWalk(walk);
}

static BOOL acceptReply(SGLyricsWalk *walk, SGLyricsProvider *provider, SGLyricsResult *fresh) {
    if (!currentWalk(walk)) return NO;
    SGLyricsQuery *query = walk.query;
    SGLyricsResult *merged = walk.merged;
    // Even a filtered reply can name the track for a deferred source.
    learnFrom(query, fresh);
    SGLyricsTypes allowed = SGLyricsSourceTypes(provider.key);
    SGKaraokeTiming timing = fresh.karaokeLines.count ? SGKaraokeLinesTiming(fresh.karaokeLines)
        : fresh.synced ? SGKaraokeTimingLine : SGKaraokeTimingNone;
    if (![provider.key isEqualToString:SGImportedLRCKey] &&
        ((allowed == SGLyricsTypesSynced && timing == SGKaraokeTimingNone) ||
         (allowed == SGLyricsTypesWords && timing != SGKaraokeTimingWords))) return YES;
    noteCredit(fresh);
    if (fresh.instrumental) {
        if (walk.concurrent) {
            walk.instrumental = YES;
            return YES;
        }
        if (walk.typeFirst && (merged.karaokeLines.count || merged.texts.count)) return YES;
        SGLog(@"lyrics: %@ is instrumental, by %@", query.trackID, provider.key);
        merged.instrumental = YES;
        finish(walk);
        return NO;
    }
    NSUInteger rank = [walk.originalOrder indexOfObject:provider.key];
    BOOL finer = betterLines(merged, fresh) || (walk.typeFirst && fresh.karaokeLines.count &&
        timing == SGKaraokeLinesTiming(merged.karaokeLines) && rank < walk.lineRank);
    // In concurrent mode the first actual word timing wins, regardless of source priority.
    if (walk.concurrent && merged.karaokeLines.count &&
        SGKaraokeLinesTiming(merged.karaokeLines) == SGKaraokeTimingWords) finer = NO;
    // Decide both replacements against the old merged answer, not the newly selected lines.
    BOOL replaceText = walk.typeFirst ? fresh.texts.count && (!merged.texts.count || timing < walk.pageTiming ||
        (timing == walk.pageTiming && rank < walk.pageRank)) : betterTexts(merged, fresh);
    if (finer) {
        walk.lineRank = rank;
        merged.karaokeLines = fresh.karaokeLines;
        merged.wordTimed = timing == SGKaraokeTimingWords;
        merged.provider = fresh.provider ?: provider.name;
    }
    if (replaceText) {
        walk.pageRank = rank;
        walk.pageTiming = timing;
        merged.starts = fresh.starts;
        merged.texts = fresh.texts;
        merged.synced = fresh.synced;
        if (!merged.provider) merged.provider = fresh.provider ?: provider.name;
        merged.pageProvider = fresh.provider ?: provider.name;
    }
    if (walk.answered && finer) {
        if (sg_kept.count >= kKeptTracks && !sg_kept[query.trackID]) [sg_kept removeAllObjects];
        sg_kept[query.trackID] = merged;
        SGLyricsSetCredit(query.trackID, merged.provider);
        if (!currentWalk(walk)) return NO;
        SGKaraokeKeepLines(query.trackID, merged.karaokeLines);
    }
    return currentWalk(walk);
}

static void step(SGLyricsWalk *walk) {
    if (!currentWalk(walk)) return;
    SGLyricsQuery *query = walk.query;
    SGLyricsResult *merged = walk.merged;
    // A source that learned the name lets earlier sources search before type first settles a tie.
    if (walk.typeFirst && walk.passedOver.count && named(query)) {
        walk.order = [walk.passedOver arrayByAddingObjectsFromArray:
            [walk.order subarrayWithRange:NSMakeRange(walk.index, walk.order.count - walk.index)]];
        walk.index = 0;
        walk.passedOver = [NSMutableArray array];
    }
    BOOL earlierPending = walk.index < walk.order.count &&
        [walk.originalOrder indexOfObject:walk.order[walk.index]] < walk.lineRank;
    if (merged.synced && merged.texts.count && merged.karaokeLines.count &&
        (!walk.typeFirst || (SGKaraokeLinesTiming(merged.karaokeLines) == SGKaraokeTimingWords && !earlierPending))) {
        finish(walk);
        return;
    }
    if (!releaseAnswer(walk)) return;
    if (walk.index >= walk.order.count) {
        // A source that matches by id named the track partway down: the ones passed over ask now,
        // in the order they came in. Once, since they cannot be passed over again with a name.
        if (walk.passedOver.count && named(query)) {
            SGLog(@"lyrics: %@ named partway as \"%@\" by \"%@\", asking %@ after all", query.trackID,
                  query.title, query.artist, [walk.passedOver componentsJoinedByString:@", "]);
            walk.order = walk.passedOver;
            walk.index = 0;
            walk.passedOver = [NSMutableArray array];
            step(walk);
            return;
        }
        finish(walk);
        return;
    }
    SGLyricsProvider *provider = SGLyricsProviderFor(walk.order[walk.index++]);
    if (provider.untimed && (merged.karaokeLines.count || merged.texts.count)) {
        step(walk);
        return;
    }
    if (provider.needsName && !named(query)) {
        [walk.passedOver addObject:provider.key];
        step(walk);
        return;
    }
    provider.ask(query, ^(SGLyricsResult *fresh) {
        if (acceptReply(walk, provider, fresh)) step(walk);
    });
}

static void askAll(SGLyricsWalk *walk) {
    if (!currentWalk(walk)) return;
    for (NSString *key in walk.originalOrder) {
        if ([walk.started containsObject:key]) continue;
        SGLyricsProvider *provider = SGLyricsProviderFor(key);
        if (provider.needsName && !named(walk.query)) continue;
        [walk.started addObject:key];
        [walk.inFlight addObject:key];
        provider.ask(walk.query, ^(SGLyricsResult *fresh) {
            // Imported files, missing keys and cached replies may answer synchronously. Every
            // initial eligible ask must start before any reply can merge or exhaust the walk.
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!currentWalk(walk) || ![walk.inFlight containsObject:key]) return;
                [walk.inFlight removeObject:key];
                if (acceptReply(walk, provider, fresh)) askAll(walk);
            });
        });
        if (!currentWalk(walk)) return;
    }
    SGLyricsResult *merged = walk.merged;
    if (!releaseAnswer(walk)) return;
    if (merged.karaokeLines.count && SGKaraokeLinesTiming(merged.karaokeLines) == SGKaraokeTimingWords &&
        merged.synced && merged.texts.count) {
        finish(walk);
        return;
    }
    if (walk.inFlight.count) return;
    // All eligible sources have started. Still-unnamed sources are not a cached miss.
    for (NSString *key in walk.originalOrder) {
        if (![walk.started containsObject:key]) [walk.passedOver addObject:key];
    }
    if (!merged.karaokeLines.count && !merged.texts.count) merged.instrumental = walk.instrumental;
    finish(walk);
}

static void scheduleWalk(SGLyricsWalk *walk) {
    if (walk.concurrent) askAll(walk);
    else step(walk);
}

static void startWalk(NSString *trackID, SGLyricsQuery *query) {
    SGLog(@"lyrics: asking %@ for %@ as \"%@\" by \"%@\", album \"%@\", %lds",
          [SGLyricsOrder() componentsJoinedByString:@", "], trackID, query.title, query.artist, query.album, (long)query.seconds);
    SGLyricsWalk *walk = [SGLyricsWalk new];
    walk.order = SGLyricsOrder();
    NSInteger mode = SGInt(SGKeyLyricsAskMode, 1);
    walk.typeFirst = mode != 0;
    walk.concurrent = mode == 2;
    walk.started = [NSMutableSet set];
    walk.inFlight = [NSMutableSet set];
    walk.originalOrder = walk.order;
    walk.lineRank = walk.pageRank = NSNotFound;
    walk.pageTiming = SGKaraokeTimingNone;
    walk.query = query;
    walk.waiting = sg_waiting[trackID];
    walk.merged = [SGLyricsResult new];
    walk.passedOver = [NSMutableArray array];
    walk.failuresAtStart = atomic_load(&sg_failures);
    NSNumber *pin = SGLyricsPinnedID(trackID);
    if (pin) {
        SGLrcLibGetID(pin, ^(SGLyricsResult *result) {
            if (!currentWalk(walk)) return;
            if (result.karaokeLines.count || result.instrumental) {
                walk.merged = result;
                finish(walk);
            } else scheduleWalk(walk);
        });
    } else scheduleWalk(walk);
}

// Starts the walk as soon as the player has named the track, or once it has waited long enough
// that it is not going to: a track opened for something other than what is playing is never named.
static void whenNamed(NSString *trackID, NSTimeInterval waited, NSMutableArray *waiting) {
    if (sg_waiting[trackID] != waiting) return;
    SGLyricsQuery *query = queryFor(trackID);
    if (named(query) || waited >= kNameWait) {
        if (!named(query)) SGLog(@"lyrics: the player never named %@ in %.1fs", trackID, waited);
        startWalk(trackID, query);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kNamePoll * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        whenNamed(trackID, waited + kNamePoll, waiting);
    });
}

void SGLyricsFetch(NSString *trackID, void (^done)(SGLyricsResult *result)) {
    setUp();
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!trackID.length) {
            done(nil);
            return;
        }
        id kept = sg_kept[trackID];
        if (kept) {
            done(kept == NSNull.null ? nil : kept);
            return;
        }
        NSMutableArray *waiting = sg_waiting[trackID];
        if (waiting) {
            [waiting addObject:[done copy]];
            return;
        }
        sg_waiting[trackID] = [NSMutableArray arrayWithObject:[done copy]];
        whenNamed(trackID, 0, sg_waiting[trackID]);
    });
}

BOOL SGLyricsMayHave(NSString *trackID) {
    setUp();
    @synchronized (sg_missing) { return ![sg_missing containsObject:trackID]; }
}

void SGLyricsPrefetch(NSString *trackID) {
    if (!trackID.length) return;
    SGLyricsFetch(trackID, ^(SGLyricsResult *result) {});
}

NSInteger SGLyricsSpotifyHas(NSString *trackID) {
    setUp();
    if (!trackID) return -1;
    @synchronized (sg_spotifyHas) {
        NSNumber *has = sg_spotifyHas[trackID];
        return has ? has.integerValue : -1;
    }
}

void SGLyricsNoteSpotifyHas(NSString *trackID, BOOL has) {
    setUp();
    if (!trackID.length) return;
    @synchronized (sg_spotifyHas) {
        NSNumber *noted = sg_spotifyHas[trackID];
        if (noted && noted.boolValue == has) return;
        if (sg_spotifyHas.count >= kNotedTracks) [sg_spotifyHas removeAllObjects];
        sg_spotifyHas[trackID] = @(has);
    }
}

NSString *const SGLyricsOwnRequestKey = @"spotifyglass.ownRequest";

// The cards under the player load together, and the list is shown without any card still loading
// once this many milliseconds have passed (NowPlaying_ScrollImpl's scrollCardsAsyncLoadingTimeoutMs,
// 2 s unless the server says otherwise, 1 s at the least). The lyrics card is one of them and waits
// for the color-lyrics reply, which with a source of the mod's on comes after the chain has answered;
// so the wait is set to the most the flag allows.
id SGLyricsForcedFlag(NSString *key) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ on = SGLyricsEnabled(); });
    if (!on) return nil;
    if ([key isEqualToString:@"ios-nowplaying-scroll-impl.scroll_cards_async_loading_timeout_ms"]) return @5000;
    return nil;
}

// After an override; no row shows the timeout, so nothing is locked.
__attribute__((constructor)) static void registerForcer(void) {
    SGRegisterFlagForcer(NO, ^id(NSString *key) { return SGLyricsForcedFlag(key); }, nil);
}

#pragma mark - the language of translations

NSArray<NSString *> *SGLyricsTranslationLanguages(void) {
    return @[@"", @"ar", @"zh-Hans", @"zh-Hant", @"cs", @"da", @"nl", @"en", @"fi", @"fr", @"de", @"el", @"he",
             @"hi", @"hu", @"id", @"it", @"ja", @"ko", @"nb", @"pl", @"pt", @"ro", @"ru", @"sk", @"es", @"sv",
             @"th", @"tr", @"uk", @"vi"];
}

NSArray<NSString *> *SGLyricsTranslationLanguageNames(void) {
    NSLocale *english = [NSLocale localeWithLocaleIdentifier:@"en"];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *tag in SGLyricsTranslationLanguages()) {
        [names addObject:tag.length ? [english localizedStringForLocaleIdentifier:tag] ?: tag : SGL(@"settings.lyricssources.translationlanguage.choice.any", @"Any · iPhone's language")];
    }
    return names;
}

NSString *SGLyricsTranslationLanguage(void) {
    NSArray<NSString *> *tags = SGLyricsTranslationLanguages();
    NSInteger index = SGInt(SGKeyLyricsTranslationLanguage, 0);
    return index > 0 && index < (NSInteger)tags.count ? tags[(NSUInteger)index] : nil;
}

NSString *SGLyricsCreditFor(NSString *trackID) {
    setUp();
    @synchronized (sg_credits) { return trackID ? sg_credits[trackID] : nil; }
}

void SGLyricsSetCredit(NSString *trackID, NSString *name) {
    setUp();
    if (!trackID.length) return;
    @synchronized (sg_credits) {
        if (sg_credits.count >= kKeptTracks) [sg_credits removeAllObjects];
        sg_credits[trackID] = name ?: @"Spotify";
    }
}

// Once, at launch: the keys Musixmatch owned alone become an order, so the Lyrics page opens on what
// the install was already doing rather than on nothing.
void SGLyricsMigrateLegacyKeys(void) {
    SGMigrateKey(SGKeyLyricsTypeFirst, SGKeyLyricsAskMode);
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:SGKeyLyricsProviders]) return;
    NSArray<NSString *> *order = fromLegacyKeys();
    if (!order.count) return;
    SGLyricsSetOrder(order);
    SGSetEnabled(SGKeyLyricsAllTracks, SGFlag(kLegacyAllTracks, NO));
    SGLog(@"lyrics: carried the Musixmatch switches over as %@", [order componentsJoinedByString:@", "]);
}

UIViewController *SGLyricsSourcesPage(void) {
    NSMutableArray<SGSource *> *all = [NSMutableArray array];
    for (SGLyricsProvider *provider in SGLyricsAllProviders()) {
        // The page is made on every open, so a key refused since the last one says so here.
        NSString *detail = [provider.key isEqualToString:SGSpicyLyricsKey] ? SGSpicyLyricsStatus() ?: provider.detail : provider.detail;
        [all addObject:[SGSource sourceWithKey:provider.key name:provider.name detail:detail]];
    }
    return SGSourcesPageMake(SGL(@"settings.lyricssources.title", @"Lyrics sources"), SGL(@"settings.lyricssources.intro", @"Drag to set source priority. Choose how sources are asked in Request mode & lyric types. In All at once mode, the first word-timed answer wins regardless of order. Deezer uses your own login cookie when you add it."),
                             all, ^NSArray<NSString *> * { return SGLyricsOrder(); }, ^(NSArray<NSString *> *keys) { SGLyricsSetOrder(keys); });
}

SGLyricsTypes SGLyricsSourceTypes(NSString *key) {
    if (!key.length || [key isEqualToString:SGImportedLRCKey]) return SGLyricsTypesAny;
    id stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:SGKeyLyricsSourceTypes][key];
    if (![stored isKindOfClass:NSNumber.class]) return SGLyricsTypesAny;
    NSInteger value = [stored integerValue];
    return value >= SGLyricsTypesAny && value <= SGLyricsTypesWords ? value : SGLyricsTypesAny;
}

void SGLyricsSetSourceTypes(NSString *key, SGLyricsTypes types) {
    if (!key.length || [key isEqualToString:SGImportedLRCKey] || types < SGLyricsTypesAny || types > SGLyricsTypesWords) return;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableDictionary *stored = [[defaults dictionaryForKey:SGKeyLyricsSourceTypes] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (types == SGLyricsTypesAny) [stored removeObjectForKey:key];
    else stored[key] = @(types);
    [defaults setObject:stored forKey:SGKeyLyricsSourceTypes];
}
