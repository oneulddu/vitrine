// The actual keeper and walk, with Spotify's hooks left out and replies held until the check lets
// them through. This exercises a choice changed while the old request is still out, without a phone.
#import <UIKit/UIKit.h>
#import "Shared/LyricsSources/LyricsSources.h"
#import "Settings/SGSourcesPage.h"
#import <objc/runtime.h>
#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #cond); exit(1); } } while (0)

static void (^sg_pinnedReply)(SGLyricsResult *);
static NSNumber *sg_askedPin;
void HarnessGetID(NSNumber *identifier, void (^done)(SGLyricsResult *)) { sg_askedPin = identifier; sg_pinnedReply = done; }
#define SGLrcLibGetID HarnessGetID
#define kKeptTracks kWalkKeptTracks
#import "Shared/LyricsSources/LyricsSources.m"
#undef kKeptTracks
#undef SGLrcLibGetID
#import "karaoke.inc"
// Exercise the production hook decisions and completion paths, without installing Logos hooks.
#define timingName hookTimingName
#define completed hookCompleted
#import "lyrics-hook.inc"
#undef completed
#undef timingName

// The rest of the app has no work in this check. The one enabled provider holds its answer.
static void (^sg_providerReply)(SGLyricsResult *);
SGLyricsAsk SGMusixmatchAsk = ^(SGLyricsQuery *q, void (^done)(SGLyricsResult *)) { sg_providerReply = done; };
SGLyricsAsk SGBiniLyricsAsk, SGUnisonAsk, SGNetEaseAsk, SGSpicyLyricsAsk, SGQQMusicAsk, SGKuGouAsk;
SGLyricsAsk SGBugsAsk, SGGenieAsk, SGLyricsPlusAsk, SGDeezerAsk, SGImportedLRCAsk;
NSString *const SGSpicyLyricsKey = @"spicylyrics", *const SGImportedLRCKey = @"importedlrc";
@implementation SGSource
+ (instancetype)sourceWithKey:(NSString *)key name:(NSString *)name detail:(NSString *)detail { return [self new]; }
@end
NSString *SGL(NSString *key, NSString *english) { return english; }
void SGMusixmatchTranslations(NSString *track, NSString *language, void (^done)(NSDictionary *)) { done(nil); }
NSArray *SGMusixmatchTranslatedLines(NSArray *lines, NSDictionary *byLine) { return nil; }
NSString *SGSpicyLyricsStatus(void) { return nil; }
UIViewController *SGTopController(void) { return nil; }
UIViewController *SGSourcesPageMake(NSString *title, NSString *note, NSArray *all, NSArray *(^order)(void), void (^setOrder)(NSArray *)) { return nil; }
void SGRegisterFlagForcer(BOOL beatsOverride, SGFlagForcer launch, SGFlagForcer locked) {}
BOOL SGRedesignedUI(void) { return NO; }
BOOL SGLocalFileIs(NSString *track) { return NO; }
NSString *SGLocalFileLyricsKey(NSString *track) { return nil; }
NSDictionary *SGLocalFileInfo(NSString *track) { return @{@"title": @"Song", @"artist": @"Singer", @"seconds": @200}; }
SGLyricsResult *SGImportedLRCFor(NSString *track, NSString *title, NSString *artist) { return nil; }
double SGSingHeldLead(void) { return 0; }
double SGSingLeadOf(SPTPlayerState *state) { return 0; }

@interface HarnessPlayer : NSObject
@property (nonatomic) double sought;
@end
@implementation HarnessPlayer
- (void)seekTo:(double)seconds { self.sought = seconds; }
@end

// AVAudioSession itself stays untouched except for its route getter while the check runs.
@interface HarnessPort : NSObject
@property (nonatomic, copy) NSString *UID, *portName, *portType;
@end
@implementation HarnessPort
@end
@interface HarnessRoute : NSObject
@property (nonatomic, copy) NSArray *outputs;
@end
@implementation HarnessRoute
@end
static HarnessRoute *sg_fakeRoute;
static id fakeRoute(id self, SEL selector) { return sg_fakeRoute; }
static void pumpUntil(BOOL (^ready)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!ready() && [limit timeIntervalSinceNow] > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    CHECK(ready());
}

@interface HarnessTask : NSObject
@property (nonatomic, strong) NSURLRequest *originalRequest, *currentRequest;
@property (nonatomic) NSURLSessionTaskState state;
@end
@implementation HarnessTask
@end

@interface HarnessDelegate : NSObject
@property (nonatomic) NSUInteger deliveries;
@end
@implementation HarnessDelegate
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    self.deliveries++;
}
@end

static void checkHookPins(void) {
    NSString *track = @"hook-song";
    SGLyricsResult *timed = SGLrcLibRecordResult(@{@"syncedLyrics": @"[00:01]Spotify timed line"});
    NSData *body = pageBody(timed, nil);
    CHECK(SGKaraokeLinesTiming(SGKaraokeLinesFromBody(body)) != SGKaraokeTimingNone);
    NSDictionary *plain = @{@"id": @800, @"plainLyrics": @"My plain choice"};
    NSDictionary *instrumental = @{@"id": @801, @"instrumental": @YES};
    for (NSDictionary *record in @[plain, instrumental]) {
        CHECK(SGLyricsPin(track, record));
        SGLyricsResult *chosen = sg_kept[track];
        NSData *page = decide(track, chosen, body, NO, nil);
        CHECK(page.length && ![page isEqual:body]);
        NSArray *kept = SGKaraokeLinesForTrack(track);
        CHECK(kept && [SGLyricsCreditFor(track) isEqual:@"LRCLIB"]);
        CHECK(![sg_requested containsObject:track]); // No Spotify timing request for a pin.
        if (chosen.instrumental) CHECK(!kept.count && !SGKaraokeLinesFromBody(page).count);
        else {
            CHECK([SGKaraokeLineText(kept.firstObject) isEqual:@"My plain choice"]);
            CHECK([SGKaraokeLineText(SGKaraokeLinesFromBody(page).firstObject) isEqual:@"My plain choice"]);
        }
    }

    // The donor's answer was accepted while this choice was current, then the user unpinned it.
    CHECK(SGLyricsPin(track, plain));
    SGLyricsTaskState *state = [SGLyricsTaskState new];
    state.kind = SGLyricsTaskDonor; state.track = track;
    state.chain = sg_kept[track]; state.pinGeneration = SGLyricsPinGeneration(track);
    HarnessDelegate *delegate = [HarnessDelegate new];
    __block NSError *ended;
    SGLyricsUnpin(track);
    CHECK(!currentChoice(state));
    finishDonor(delegate, nil, nil, state, body, nil, ^(NSError *error) { ended = error; });
    CHECK(ended.code == NSURLErrorCancelled && !delegate.deliveries && !SGKaraokeLinesForTrack(track));
    // Even the same record pinned again is a different choice; the old donor cannot write it back.
    CHECK(SGLyricsPin(track, instrumental));
    ended = nil;
    finishDonor(delegate, nil, nil, state, body, nil, ^(NSError *error) { ended = error; });
    CHECK(ended.code == NSURLErrorCancelled && !delegate.deliveries && !SGKaraokeLinesForTrack(track).count);

    // Capture at request creation, not response arrival, including when donor mode is disabled.
    NSURL *url = [NSURL URLWithString:@"https://spclient.wg.spotify.com/color-lyrics/v2/track/hook-song"];
    HarnessTask *task = [HarnessTask new];
    task.originalRequest = lyricsRequestFor([NSURLRequest requestWithURL:url]);
    task.currentRequest = task.originalRequest;
    NSUInteger generation = SGLyricsPinGeneration(track);
    CHECK([[NSURLProtocol propertyForKey:kPinGenerationKey inRequest:task.originalRequest] unsignedIntegerValue] == generation);
    CHECK(!SGLyricsPin(track, @{@"id": @1}) && SGLyricsPinGeneration(track) == generation);
    CHECK(SGLyricsPin(track, plain));
    CHECK([[NSURLProtocol propertyForKey:kPinGenerationKey inRequest:lyricsRequestFor(task.originalRequest)] unsignedIntegerValue] == generation);
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/2" headerFields:nil];
    state = classify((id)task, response);
    CHECK(state.pinGeneration == generation && !currentChoice(state));
    ended = nil;
    finishSpotify(delegate, nil, (id)task, state, body, nil, ^(NSError *error) { ended = error; });
    CHECK(ended.code == NSURLErrorCancelled && !delegate.deliveries);
    __block BOOL cancelled = NO, forwarded = NO;
    state.kind = SGLyricsTaskDonor;
    answerHeld(delegate, nil, (id)task, state, timed, response,
               ^(NSURLSessionResponseDisposition choice) { cancelled = choice == NSURLSessionResponseCancel; },
               ^(NSURLResponse *given, SGDisposition handler) { forwarded = YES; });
    CHECK(cancelled && !forwarded && !delegate.deliveries);

    // Donor rewriting carries the generation of the real track, even before any response exists.
    SGLyricsNoteSpotifyHas(track, NO);
    sg_everyTrack = YES;
    NSURLRequest *donor = lyricsRequestFor([NSURLRequest requestWithURL:url]);
    sg_everyTrack = NO;
    CHECK([donorFor(donor) isEqual:track] && [lyricsTrack(donor.URL) isEqual:kDonorTrack]);
    task.originalRequest = task.currentRequest = donor;
    CHECK(SGLyricsPin(track, instrumental));
    SGLyricsTaskState *donorState = classify((id)task, response);
    CHECK(donorState.kind == SGLyricsTaskDonor && !currentChoice(donorState));

    // Also change the pin while finishSpotify is waiting for its source callback.
    state.pinGeneration = SGLyricsPinGeneration(track);
    ended = nil;
    finishSpotify(delegate, nil, (id)task, state, body, nil, ^(NSError *error) { ended = error; });
    CHECK(SGLyricsPin(track, instrumental));
    pumpUntil(^BOOL { return ended != nil; });
    CHECK(ended.code == NSURLErrorCancelled && !delegate.deliveries && !SGKaraokeLinesForTrack(track).count);
    CHECK([SGLyricsCreditFor(track) isEqual:@"LRCLIB"]);
    printf("hook pins: plain/instrumental beat late Spotify timing; stale donor, held and Spotify replies dropped after pin/unpin passed\n");
}

static NSUserDefaults *sg_testDefaults;
static NSString *sg_testSuite;
static NSUInteger sg_defaultsReads;
static id fakeDefaults(id self, SEL selector) { sg_defaultsReads++; return sg_testDefaults; }
static void removeTestDefaults(void) { [sg_testDefaults removePersistentDomainForName:sg_testSuite]; }

static void checkLanguageStore(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL translation = YES, pronunciation = YES;
    CHECK(!SGLyricsLanguageRule(@"ja", &translation, &pronunciation) && translation && pronunciation);
    SGLyricsSetLanguageRule(@"ja-JP", YES, NO);
    CHECK(SGLyricsLanguageRule(@"ja", &translation, &pronunciation) && translation && !pronunciation);
    CHECK(SGLyricsLanguageRule(@"ja", NULL, NULL));
    SGLyricsSetLanguageRule(@"ja", NO, YES);
    CHECK(SGLyricsLanguageRule(@"ja", &translation, &pronunciation) && !translation && pronunciation);
    CHECK([defaults dictionaryForKey:SGKeyLyricsLanguageRules].count == 1);
    SGLyricsSetLanguageRule(@"invalid tag", YES, YES);
    CHECK([defaults dictionaryForKey:SGKeyLyricsLanguageRules].count == 1);
    [defaults setObject:@{@"ko": @"invalid"} forKey:SGKeyLyricsLanguageRules];
    CHECK(!SGLyricsLanguageRule(@"ko", NULL, NULL));
    [defaults removeObjectForKey:SGKeyLyricsLanguageRules];
    CHECK(!SGLyricsLanguageRule(@"ja", NULL, NULL));
    __block NSUInteger notes = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:SGLyricsLanguageDidChangeNotification object:@"language-song" queue:nil usingBlock:^(NSNotification *note) {
        CHECK(NSThread.isMainThread); notes++;
    }];
    NSArray *japanese = SGKaraokeStaticLines(@[@"明日の空を見上げて歩く"]);
    SGLyricsSetTrackLanguage(@"language-song", @"EN_us");
    CHECK([SGLyricsSongLanguage(@"language-song", japanese) isEqual:@"en-us"] && notes == 1);
    SGLyricsSetTrackLanguage(@"language-song", nil);
    CHECK(!SGLyricsTrackLanguage(@"language-song") && notes == 2);
    CHECK([SGLyricsSongLanguage(@"language-song", japanese) isEqual:@"ja"]);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ SGLyricsSetTrackLanguage(@"language-song", @"ko"); });
    pumpUntil(^BOOL { return notes == 3; });
    CHECK([SGLyricsTrackLanguage(@"language-song") isEqual:@"ko"]);
    for (NSUInteger i = 0; i < 501; i++) SGLyricsSetTrackLanguage(@(i).stringValue, @"es");
    CHECK([defaults dictionaryForKey:SGKeyLyricsTrackLanguages].count == 500 && [SGLyricsTrackLanguage(@"500") isEqual:@"es"]);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    printf("language store: rules, nullable outputs, malformed entries, overrides, removal, main notification and 500 tracks passed\n");
}

static SGLyricsResult *madeUpLyrics(NSString *name, SGKaraokeTiming timing) {
    NSArray *lines = timing == SGKaraokeTimingNone ? SGKaraokeStaticLines(@[name]) : SGKaraokeEstimatedLines(@[@1000], @[name]);
    for (SGKaraokeLine *line in lines) line.timing = timing;
    return SGLyricsResultWithLines(lines, name);
}

static void checkWalkTypes(void) {
    NSArray *keys = @[@"musixmatch", @"netease", @"unison"];
    NSMutableArray *saved = [NSMutableArray array], *asked = [NSMutableArray array];
    NSMutableDictionary *replies = [NSMutableDictionary dictionary];
    for (NSString *key in [keys arrayByAddingObject:SGImportedLRCKey]) {
        SGLyricsProvider *provider = SGLyricsProviderFor(key);
        [saved addObject:(id)provider.ask ?: NSNull.null];
        provider.ask = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) {
            [asked addObject:key]; done(replies[key]);
        };
    }
    void (^run)(BOOL, SGLyricsTypes, SGKaraokeTiming, SGKaraokeTiming, NSArray *, NSString *) =
    ^(BOOL typeFirst, SGLyricsTypes allowed, SGKaraokeTiming first, SGKaraokeTiming second, NSArray *expected, NSString *winner) {
        [asked removeAllObjects];
        SGLyricsSetOrder(keys);
        SGSetEnabled(SGKeyLyricsTypeFirst, typeFirst);
        SGLyricsSetSourceTypes(keys[0], allowed);
        replies[keys[0]] = madeUpLyrics(keys[0], first);
        replies[keys[1]] = madeUpLyrics(keys[1], second);
        replies[keys[2]] = madeUpLyrics(keys[2], SGKaraokeTimingLine);
        __block SGLyricsResult *answer;
        SGLyricsFetch(NSUUID.UUID.UUIDString, ^(SGLyricsResult *result) { answer = result; });
        pumpUntil(^BOOL { return answer != nil; });
        CHECK([asked isEqual:expected]);
        CHECK([answer.provider isEqual:winner] && [answer.pageProvider isEqual:winner]);
    };
    run(NO, SGLyricsTypesAny, SGKaraokeTimingLine, SGKaraokeTimingWords, @[keys[0]], keys[0]);
    run(YES, SGLyricsTypesAny, SGKaraokeTimingLine, SGKaraokeTimingWords, @[keys[0], keys[1]], keys[1]);
    run(YES, SGLyricsTypesAny, SGKaraokeTimingLine, SGKaraokeTimingLine, keys, keys[0]);
    run(YES, SGLyricsTypesAny, SGKaraokeTimingWords, SGKaraokeTimingWords, @[keys[0]], keys[0]);
    run(NO, SGLyricsTypesSynced, SGKaraokeTimingNone, SGKaraokeTimingLine, @[keys[0], keys[1]], keys[1]);
    run(NO, SGLyricsTypesWords, SGKaraokeTimingLine, SGKaraokeTimingWords, @[keys[0], keys[1]], keys[1]);
    run(NO, SGLyricsTypesSynced, SGKaraokeTimingLine, SGKaraokeTimingWords, @[keys[0]], keys[0]);
    run(NO, SGLyricsTypesWords, SGKaraokeTimingWords, SGKaraokeTimingWords, @[keys[0]], keys[0]);
    run(YES, SGLyricsTypesAny, SGKaraokeTimingNone, SGKaraokeTimingLine, keys, keys[1]);
    [asked removeAllObjects];
    SGLyricsSetOrder(@[SGImportedLRCKey]);
    [NSUserDefaults.standardUserDefaults setObject:@{SGImportedLRCKey: @(SGLyricsTypesWords)} forKey:SGKeyLyricsSourceTypes];
    replies[SGImportedLRCKey] = madeUpLyrics(@"Imported", SGKaraokeTimingNone);
    __block SGLyricsResult *answer;
    SGLyricsFetch(NSUUID.UUID.UUIDString, ^(SGLyricsResult *result) { answer = result; });
    pumpUntil(^BOOL { return answer != nil; });
    CHECK([answer.provider isEqual:@"Imported"] && SGLyricsSourceTypes(SGImportedLRCKey) == SGLyricsTypesAny);
    // The first source needed the name that the second source discovers. It still wins a tie.
    [asked removeAllObjects];
    SGLyricsSetOrder(@[keys[1], keys[0], keys[2]]);
    replies[keys[0]] = madeUpLyrics(keys[0], SGKaraokeTimingWords);
    replies[keys[1]] = madeUpLyrics(keys[1], SGKaraokeTimingWords);
    ((SGLyricsResult *)replies[keys[0]]).title = @"Named later";
    ((SGLyricsResult *)replies[keys[0]]).artist = @"Singer";
    SGLyricsQuery *unnamed = [SGLyricsQuery new]; unnamed.trackID = NSUUID.UUID.UUIDString;
    answer = nil;
    sg_waiting[unnamed.trackID] = [NSMutableArray arrayWithObject:[^(SGLyricsResult *result) { answer = result; } copy]];
    startWalk(unnamed.trackID, unnamed);
    CHECK([asked isEqual:(@[keys[0], keys[1]])] && [answer.provider isEqual:keys[1]] && [answer.pageProvider isEqual:keys[1]]);
    NSUInteger index = 0;
    for (NSString *key in [keys arrayByAddingObject:SGImportedLRCKey]) {
        id original = saved[index++]; SGLyricsProviderFor(key).ask = original == NSNull.null ? nil : original;
    }
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyLyricsSourceTypes];
    SGSetEnabled(SGKeyLyricsTypeFirst, NO);
    SGLyricsSetOrder(@[@"musixmatch"]);
    printf("walk types: default early stop, type-first upgrade and ties including late naming, any/synced/words filtering and imported bypass passed\n");
}

static void checkWalkEarlyAnswer(void) {
    NSArray *keys = @[@"musixmatch", @"netease", @"unison"];
    NSMutableArray *saved = [NSMutableArray array], *asked = [NSMutableArray array];
    NSMutableDictionary *pending = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        SGLyricsProvider *provider = SGLyricsProviderFor(key);
        [saved addObject:(id)provider.ask ?: NSNull.null];
        provider.ask = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) {
            [asked addObject:key]; pending[key] = [done copy];
        };
    }
    SGSetEnabled(SGKeyLyricsTypeFirst, YES);
    SGLyricsSetOrder(keys);
    for (NSString *action in @[@"upgrade", @"pin", @"reload", @"filter"]) {
        NSString *track = [@"early-" stringByAppendingString:action];
        [asked removeAllObjects]; [pending removeAllObjects];
        SGLyricsResult *line = madeUpLyrics(@"First lines", SGKaraokeTimingLine);
        SGLyricsResult *words = madeUpLyrics(@"Later words", SGKaraokeTimingWords);
        __block NSUInteger deliveries = 0, hookEnds = 0;
        for (NSUInteger i = 0; i < 2; i++) SGLyricsFetch(track, ^(SGLyricsResult *result) {
            CHECK(SGKaraokeLinesTiming(result.karaokeLines) == SGKaraokeTimingLine);
            CHECK([result.provider isEqual:line.provider]);
            deliveries++;
        });
        SGKaraokeRequestLyrics(track);
        // The color-lyrics completion is a waiter too; it must deliver before the second source.
        HarnessDelegate *delegate = [HarnessDelegate new];
        SGLyricsTaskState *state = [SGLyricsTaskState new];
        state.track = track; state.pinGeneration = SGLyricsPinGeneration(track);
        finishSpotify(delegate, nil, nil, state, pageBody(line, nil), nil, ^(NSError *error) {
            CHECK(!error); hookEnds++;
        });
        pumpUntil(^BOOL { return pending[keys[0]] && sg_waiting[track].count == 4; });
        CHECK(!deliveries && !hookEnds && !pending[keys[1]]);
        void (^first)(SGLyricsResult *) = pending[keys[0]];
        first(line);
        CHECK(deliveries == 2 && hookEnds == 1 && delegate.deliveries == 1);
        CHECK(sg_waiting[track] && !sg_waiting[track].count && pending[keys[1]]);
        CHECK(SGKaraokeLinesTiming(SGKaraokeLinesForTrack(track)) == SGKaraokeTimingLine);
        CHECK([SGLyricsCreditFor(track) isEqual:line.provider]);
        __block SGLyricsResult *cached;
        SGLyricsFetch(track, ^(SGLyricsResult *result) { cached = result; });
        pumpUntil(^BOOL { return cached != nil; });
        CHECK(cached == sg_kept[track] && [cached.provider isEqual:line.provider]);
        CHECK([asked isEqual:(@[keys[0], keys[1]])]);
        void (^late)(SGLyricsResult *) = pending[keys[1]];

        if ([action isEqual:@"pin"]) {
            CHECK(SGLyricsPin(track, @{@"id": @901, @"syncedLyrics": @"[00:01]Pinned lines"}));
            SGLyricsResult *pinned = sg_kept[track];
            NSArray *pinnedLines = SGKaraokeLinesForTrack(track);
            late(words);
            CHECK(sg_kept[track] == pinned && SGKaraokeLinesForTrack(track) == pinnedLines);
            CHECK([SGLyricsCreditFor(track) isEqual:@"LRCLIB"] && !sg_waiting[track]);
            // Even after cache eviction, a successful pinned answer never continues the order.
            [sg_kept removeObjectForKey:track]; sg_pinnedReply = nil;
            __block SGLyricsResult *pinAnswer;
            SGLyricsFetch(track, ^(SGLyricsResult *result) { pinAnswer = result; });
            pumpUntil(^BOOL { return sg_pinnedReply != nil; });
            sg_pinnedReply(pinned);
            CHECK(pinAnswer == pinned && !sg_waiting[track] && asked.count == 2);
        } else if ([action isEqual:@"reload"]) {
            NSUInteger generation = SGLyricsPinGeneration(track);
            SGLyricsReload(track);
            CHECK(SGLyricsPinGeneration(track) == generation + 1);
            CHECK(!sg_kept[track] && !SGKaraokeLinesForTrack(track) && !SGLyricsCreditFor(track));
            late(words);
            CHECK(!sg_kept[track] && !SGKaraokeLinesForTrack(track) && !SGLyricsCreditFor(track));
            pumpUntil(^BOOL { return sg_waiting[track].count == 1; });
            CHECK(asked.count == 3 && [asked.lastObject isEqual:keys[0]]);
            void (^reloaded)(SGLyricsResult *) = pending[keys[0]];
            reloaded(madeUpLyrics(@"Reloaded words", SGKaraokeTimingWords));
            SGLyricsResult *kept = sg_kept[track];
            NSArray *keptLines = SGKaraokeLinesForTrack(track);
            late(words);
            CHECK(sg_kept[track] == kept && SGKaraokeLinesForTrack(track) == keptLines);
            CHECK([SGLyricsCreditFor(track) isEqual:@"Reloaded words"] && !sg_waiting[track]);
        } else {
            if ([action isEqual:@"filter"]) {
                SGLyricsSetSourceTypes(keys[1], SGLyricsTypesWords);
                NSArray *before = SGKaraokeLinesForTrack(track);
                late(madeUpLyrics(@"Rejected lines", SGKaraokeTimingLine));
                CHECK(SGKaraokeLinesForTrack(track) == before && [SGLyricsCreditFor(track) isEqual:line.provider]);
                CHECK(pending[keys[2]] && sg_waiting[track]);
                late = pending[keys[2]];
            }
            late(words);
            SGLyricsResult *kept = sg_kept[track];
            CHECK(SGKaraokeLinesTiming(kept.karaokeLines) == SGKaraokeTimingWords);
            CHECK([kept.provider isEqual:words.provider] && [kept.pageProvider isEqual:words.provider]);
            CHECK(SGKaraokeLinesTiming(SGKaraokeLinesForTrack(track)) == SGKaraokeTimingWords);
            CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:words.provider]);
            CHECK([SGLyricsCreditFor(track) isEqual:words.provider] && !sg_waiting[track]);
        }
        CHECK(deliveries == 2 && hookEnds == 1 && delegate.deliveries == 1);
        SGLyricsSetSourceTypes(keys[1], SGLyricsTypesAny);
    }
    NSUInteger index = 0;
    for (NSString *key in keys) {
        id original = saved[index++]; SGLyricsProviderFor(key).ask = original == NSNull.null ? nil : original;
    }
    SGSetEnabled(SGKeyLyricsTypeFirst, NO);
    SGLyricsSetOrder(@[@"musixmatch"]);
    printf("type-first early answer: waiters and color-lyrics released before later source; cached answer, word upgrade, credit, filters, pin and reload rejection passed\n");
}

static void checkReload(void) {
    NSString *track = @"reload-song";
    NSDictionary *record = @{@"id": @456, @"syncedLyrics": @"[00:01]Before reload"};
    CHECK(SGLyricsPin(track, record));
    NSUInteger generation = SGLyricsPinGeneration(track);
    __block NSUInteger notes = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:SGLyricsDidReloadNotification object:track queue:nil usingBlock:^(NSNotification *note) {
        CHECK(NSThread.isMainThread && !sg_kept[track] && !SGKaraokeLinesForTrack(track) && !SGLyricsCreditFor(track));
        CHECK(![sg_requested containsObject:track] && ![sg_asking containsObject:track] && !sg_losses[track] && !sg_requests[track]);
        CHECK(SGLyricsMayHave(track)); notes++;
    }];
    [sg_missing addObject:track]; sg_losses[track] = @3;
    sg_pinnedReply = nil;
    SGLyricsReload(track);
    CHECK(notes == 1 && [SGLyricsPinnedID(track) isEqual:@456] && SGLyricsPinGeneration(track) == generation + 1);
    pumpUntil(^BOOL { return sg_pinnedReply != nil; });
    void (^old)(SGLyricsResult *) = sg_pinnedReply;
    sg_pinnedReply = nil;
    SGLyricsReload(track);
    old(SGLrcLibRecordResult(record));
    CHECK(!SGKaraokeLinesForTrack(track) && !sg_kept[track]);
    pumpUntil(^BOOL { return sg_pinnedReply != nil; });
    sg_pinnedReply(SGLrcLibRecordResult(@{@"syncedLyrics": @"[00:02]After reload"}));
    pumpUntil(^BOOL { return SGKaraokeLinesForTrack(track) != nil; });
    CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"After reload"]);
    CHECK([sg_askedPin isEqual:@456] && [SGLyricsCreditFor(track) isEqual:@"LRCLIB"]);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    printf("reload: cleared caches, request generations, notification order, kept pin and stale reply rejection passed\n");
}

int main(void) {
    @autoreleasepool {
        // A separate suite makes the default writes real without touching the app's or the user's.
        sg_testSuite = [@"com.vitrine.lyrics-state-check." stringByAppendingString:NSUUID.UUID.UUIDString];
        sg_testDefaults = [[NSUserDefaults alloc] initWithSuiteName:sg_testSuite];
        atexit(removeTestDefaults);
        Method defaultsMethod = class_getClassMethod(NSUserDefaults.class, @selector(standardUserDefaults));
        method_setImplementation(defaultsMethod, (IMP)fakeDefaults);
        NSUserDefaults *defaults = sg_testDefaults;
        checkLanguageStore();
        [defaults setObject:@[@"musixmatch"] forKey:SGKeyLyricsProviders];
        [defaults setInteger:250 forKey:SGKeyLyricsDelay];
        sg_seenTracks = [NSMutableDictionary dictionary];
        sg_lyrics = [NSMutableDictionary dictionary];
        sg_requested = [NSMutableSet set]; sg_asking = [NSMutableSet set]; sg_looking = [NSMutableSet set];
        sg_losses = [NSMutableDictionary dictionary]; sg_ownSources = YES;
        sg_lastSeenID = @"song";
        HarnessPort *port = [HarnessPort new]; port.UID = @"headphones-one"; port.portName = @"Headphones"; port.portType = AVAudioSessionPortBluetoothA2DP;
        sg_fakeRoute = [HarnessRoute new]; sg_fakeRoute.outputs = @[port];
        Method routeMethod = class_getInstanceMethod(AVAudioSession.class, @selector(currentRoute));
        IMP originalRoute = method_setImplementation(routeMethod, (IMP)fakeRoute);
        CHECK(SGKaraokeDelayMs() == 250);
        NSUInteger reads = sg_defaultsReads;
        dispatch_apply(1000, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t i) { CHECK(SGKaraokeDelayMs() == 250); });
        CHECK(sg_defaultsReads == reads);
        SGSetInt(SGKeyLyricsDelay, 500);
        CHECK(SGKaraokeDelayMs() == 500);
        SGSetInt(SGKeyLyricsDelay, 250);
        SGLyricsSetTrackOffsetMs(@"song", -6000);
        SGLyricsSetRouteOffsetMs(6000);
        CHECK(SGLyricsTrackOffsetMs(@"song") == -5000 && SGLyricsRouteOffsetMs() == 5000 && SGKaraokeDelayMs() == 250);
        SGLyricsSetRouteOffsetMs(-300);
        CHECK(SGKaraokeDelayMs() == -5050 && [SGLyricsRouteName() isEqual:@"Headphones"]);
        SGLyricsSetTrackOffsetMs(@"song", 0);
        CHECK(SGKaraokeDelayMs() == -50 && ![defaults dictionaryForKey:SGKeyLyricsTrackOffsets][@"song"]);
        for (NSUInteger i = 0; i < 501; i++) SGLyricsSetTrackOffsetMs([@(i) stringValue], 12);
        CHECK([defaults dictionaryForKey:SGKeyLyricsTrackOffsets].count == 500 && SGLyricsTrackOffsetMs(@"500") == 12);
        __block NSUInteger routeNotes = 0;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:SGLyricsOffsetsDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            CHECK(NSThread.isMainThread); routeNotes++;
        }];
        port.portType = AVAudioSessionPortBuiltInSpeaker;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:AVAudioSessionRouteChangeNotification object:nil];
        });
        pumpUntil(^BOOL { return routeNotes > 0; });
        CHECK(!SGLyricsRouteName() && !SGLyricsRouteOffsetMs() && SGKaraokeDelayMs() == 250);
        SGLyricsSetRouteOffsetMs(1000);
        CHECK(!SGLyricsRouteOffsetMs());
        port.portType = AVAudioSessionPortBluetoothA2DP;
        [NSNotificationCenter.defaultCenter postNotificationName:AVAudioSessionRouteChangeNotification object:nil];
        pumpUntil(^BOOL { return routeNotes > 1; });
        CHECK(SGLyricsRouteOffsetMs() == -300);
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        HarnessPlayer *player = [HarnessPlayer new]; sg_player = player;
        SGKaraokeSeek(-500); CHECK(player.sought == 0);
        method_setImplementation(routeMethod, originalRoute);
        printf("offsets: clamp, zero removal, 500 tracks, negative total, cached clock, route notification and seek passed\n");

        NSDictionary *record = @{@"id": @123, @"syncedLyrics": @"[00:01]Chosen line"};
        __block NSUInteger pinNotes = 0;
        observer = [NSNotificationCenter.defaultCenter addObserverForName:SGLyricsPinDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            CHECK(NSThread.isMainThread);
            if (SGLyricsPinnedID(note.object)) CHECK(SGKaraokeLinesForTrack(note.object) != nil);
            pinNotes++;
        }];
        __block SGLyricsResult *answer;
        SGLyricsFetch(@"song", ^(SGLyricsResult *result) { answer = result; });
        pumpUntil(^BOOL { return sg_providerReply != nil; });
        void (^oldReply)(SGLyricsResult *) = sg_providerReply;
        CHECK(SGLyricsPin(@"song", record));
        CHECK([SGLyricsPinnedID(@"song") isEqual:@123] && answer.karaokeLines.count == 1 && pinNotes == 1);
        CHECK([SGLyricsCreditFor(@"song") isEqual:@"LRCLIB"]);
        SGLyricsResult *chosen = answer;
        oldReply(SGLyricsPlainResult(@"Late wrong words", @"Old provider"));
        CHECK(sg_kept[@"song"] == chosen && [SGKaraokeLineText(SGKaraokeLinesForTrack(@"song").firstObject) isEqual:@"Chosen line"]);
        CHECK(!SGLyricsPin(@"song", @{@"id": @456}) && [SGLyricsPinnedID(@"song") isEqual:@123] && pinNotes == 1);
        SGLyricsUnpin(@"song");
        CHECK(!SGLyricsPinnedID(@"song") && !SGKaraokeLinesForTrack(@"song") && SGLyricsMayHave(@"song") && pinNotes == 2);
        sg_providerReply = nil;
        pumpUntil(^BOOL { return sg_providerReply != nil; });
        sg_providerReply(SGLrcLibRecordResult(@{@"syncedLyrics": @"[00:02]Normal again"}));
        CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(@"song").firstObject) isEqual:@"Normal again"]);
        CHECK(SGLyricsPin(@"song", record));
        [sg_kept removeObjectForKey:@"song"]; // The walk cache was evicted, so the persistent id must be asked first.
        answer = nil;
        SGLyricsFetch(@"song", ^(SGLyricsResult *result) { answer = result; });
        pumpUntil(^BOOL { return sg_pinnedReply != nil; });
        CHECK([sg_askedPin isEqual:@123]);
        void (^oldPinReply)(SGLyricsResult *) = sg_pinnedReply;
        SGLyricsUnpin(@"song");
        oldPinReply(chosen);
        CHECK(!answer && !sg_kept[@"song"]);
        sg_providerReply(SGLrcLibRecordResult(@{@"syncedLyrics": @"[00:03]After unpin"}));
        CHECK([SGKaraokeLineText(answer.karaokeLines.firstObject) isEqual:@"After unpin"]);
        CHECK(SGLyricsPin(@"fallback", record));
        [sg_kept removeObjectForKey:@"fallback"];
        sg_pinnedReply = nil; sg_providerReply = nil; answer = nil;
        SGLyricsFetch(@"fallback", ^(SGLyricsResult *result) { answer = result; });
        pumpUntil(^BOOL { return sg_pinnedReply != nil; });
        CHECK(!sg_providerReply);
        sg_pinnedReply(nil);
        CHECK(sg_providerReply != nil);
        sg_providerReply(SGLrcLibRecordResult(@{@"plainLyrics": @"Fallback words"}));
        CHECK([SGKaraokeLineText(answer.karaokeLines.firstObject) isEqual:@"Fallback words"]);
        CHECK(SGLyricsPin(@"instrumental", @{@"id": @9, @"instrumental": @YES}));
        CHECK(SGKaraokeLinesForTrack(@"instrumental") && !SGKaraokeLinesForTrack(@"instrumental").count);
        checkHookPins();
        checkWalkTypes();
        checkWalkEarlyAnswer();
        checkReload();
        for (NSUInteger i = 0; i < 501; i++) CHECK(SGLyricsPin([@(i) stringValue], record));
        CHECK([defaults dictionaryForKey:SGKeyLyricsPins].count == 500 && [SGLyricsPinnedID(@"500") isEqual:@123]);
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        printf("pins: immediate keep, invalid choice, stale walk, unpin, stored-id lookup, failed-pin fallback, instrumental and 500 pins passed\n");
    }
    return 0;
}
