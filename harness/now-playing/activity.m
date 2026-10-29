// The real LiveActivity.x timer and reader, with only ActivityKit/player services replaced.
#import <UIKit/UIKit.h>
#import "artwork.h"
#import "Shared/LiveActivity/LiveActivity.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SleepTimer.h"

static NSString *sentTranslation, *sentLine;
@interface SGLiveActivityBridge : NSObject
@end
@implementation SGLiveActivityBridge
+ (BOOL)isShowing { return YES; }
+ (NSDate *)startedAt { return [NSDate date]; }
+ (BOOL)canStart { return YES; }
+ (void)end {}
+ (void)endBeforeExit {}
+ (void)showWithView:(NSInteger)view paused:(BOOL)paused line:(NSString *)line nextLine:(NSString *)nextLine
              titles:(NSArray *)titles artists:(NSArray *)artists uris:(NSArray *)uris
                 tab:(NSInteger)tab title:(NSString *)title artist:(NSString *)artist shuffle:(BOOL)shuffle repeatMode:(NSInteger)repeatMode
            timerEnd:(NSDate *)timerEnd timerEndOfTrack:(BOOL)timerEndOfTrack timerEndOfAlbum:(BOOL)timerEndOfAlbum
                tint:(NSString *)tint trackStart:(NSDate *)trackStart trackEnd:(NSDate *)trackEnd pausedAt:(NSNumber *)pausedAt
         translation:(NSString *)translation cover:(NSData *)cover textSize:(NSInteger)textSize
           alignment:(NSInteger)alignment noLyrics:(BOOL)noLyrics withoutLyrics:(NSInteger)withoutLyrics
             colors:(NSInteger)colors accent:(NSString *)accent progressBar:(BOOL)progressBar {
    sentLine = line;
    sentTranslation = translation;
}
@end

BOOL SGLyricsPiPActive(void) { return NO; }
NSNotificationName const SGLyricsPiPDidChangeNotification = @"harness.pip";
BOOL SGKaraokeLooking(NSString *track) { return NO; }
NSArray *SGPlayerUpcomingTracks(SPTPlayerState *state, NSUInteger limit) { return @[]; }
id SGPlayerAdvanceRepeat(id player, id options) { return nil; }
SGSleepTimerMode SGSleepTimerCurrentMode(void) { return SGSleepTimerOff; }
NSDate *SGSleepTimerEnd(void) { return nil; }
void SGSetSleepTimer(SGSleepTimerMode mode, NSTimeInterval seconds) {}
void SGSleepTimerAdd(NSTimeInterval seconds) {}
BOOL SGSingOn(void) { return NO; }
NSString *SGSingMissing(void) { return nil; }
void SGSetSingOn(BOOL on) {}
BOOL SGLikePlayingTrack(void) { return NO; }

static void refresh(void) {
    // The card's normal action notification asks its timer owner to publish now.
    [NSNotificationCenter.defaultCenter postNotificationName:@"SGLiveActivityAction" object:@"tab:0"];
    runFor(.05);
}

void activityChecks(void) {
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLiveActivityTranslation: @YES} forName:NSArgumentDomain];
    harnessLanguage = @"en";
    harnessTranslations = @{@"en": @{@"Hola": @"Hello restored"}, @"ko": @{@"Hola": @"안녕"}};
    harnessState(@"activity-restore", @"Song");
    harnessLines(@[lineOf(@"Hola", 0, 10000)]);
    NSUInteger automaticBefore = harnessAutomaticTranslations;
    SGSetLiveActivityEnabled(YES);
    refresh();
    check([sentLine isEqual:@"Hola"] && [sentTranslation isEqual:@"Hello restored"],
          @"Live Activity restores saved generated translation without opening lyrics");

    harnessLanguage = @"ko";
    refresh();
    check([sentTranslation isEqual:@"안녕"], @"Live Activity reloads saved translation after language change");
    harnessTranslations = nil;
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];
    runFor(.05);
    check(!sentTranslation.length, @"paused Live Activity clears deleted translation without a view");

    harnessTranslations = @{@"ko": @{@"Hola": @"다시"}};
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationSavedNotification
        object:@"activity-restore" userInfo:@{@"language": @"ko"}];
    runFor(.05);
    check([sentTranslation isEqual:@"다시"], @"paused Live Activity refreshes a saved translation");

    harnessHoldTranslation = YES;
    harnessLanguage = @"en";
    harnessTranslations = @{@"en": @{@"Hola": @"Stale English"}, @"ko": @{@"Hola": @"새 소스"}};
    refresh();
    harnessLanguage = @"ko";
    refresh();
    harnessHoldTranslation = NO;
    harnessDeliverTranslations();
    runFor(.05);
    check([sentTranslation isEqual:@"새 소스"], @"late retired-language load cannot overwrite the current activity");
    harnessTranslations = @{@"ko": @{@"Hola": @"다른 소스"}};
    harnessLines(@[lineOf(@"Hola", 0, 10000)]);
    refresh();
    check([sentTranslation isEqual:@"다른 소스"], @"Live Activity restores translations onto replacement source lines");
    check(harnessAutomaticTranslations == automaticBefore, @"Live Activity never starts automatic translation");
    SGSetLiveActivityEnabled(NO);
    harnessTranslations = nil;
    harnessLanguage = @"en";
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{} forName:NSArgumentDomain];
}
