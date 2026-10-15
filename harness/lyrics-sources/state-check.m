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

int main(void) {
    @autoreleasepool {
        // A separate suite makes the default writes real without touching the app's or the user's.
        sg_testSuite = [@"com.vitrine.lyrics-state-check." stringByAppendingString:NSUUID.UUID.UUIDString];
        sg_testDefaults = [[NSUserDefaults alloc] initWithSuiteName:sg_testSuite];
        atexit(removeTestDefaults);
        Method defaultsMethod = class_getClassMethod(NSUserDefaults.class, @selector(standardUserDefaults));
        method_setImplementation(defaultsMethod, (IMP)fakeDefaults);
        NSUserDefaults *defaults = sg_testDefaults;
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
        for (NSUInteger i = 0; i < 501; i++) CHECK(SGLyricsPin([@(i) stringValue], record));
        CHECK([defaults dictionaryForKey:SGKeyLyricsPins].count == 500 && [SGLyricsPinnedID(@"500") isEqual:@123]);
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        printf("pins: immediate keep, invalid choice, stale walk, unpin, stored-id lookup, failed-pin fallback, instrumental and 500 pins passed\n");
    }
    return 0;
}
