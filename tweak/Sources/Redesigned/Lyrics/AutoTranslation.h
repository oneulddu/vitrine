// Automatic requests belong to the redesigned lyrics view; translators and saved results stay shared.
#import <Foundation/Foundation.h>
@class SGModRow, SGKaraokeLine;
#define SGRKeyLyricsAutoTranslation @"spotifyglass.redesign.lyrics.autoTranslation"
#define SGRKeyLyricsAutoTranslationOrder @"spotifyglass.redesign.lyrics.autoTranslationOrder"
typedef NS_ENUM(NSInteger, SGRAutoTranslator) {
    SGRAutoTranslatorOff = 0, SGRAutoTranslatorOnDevice, SGRAutoTranslatorAppleIntelligence,
    SGRAutoTranslatorGoogle, SGRAutoTranslatorBing, SGRAutoTranslatorDeepL,
    SGRAutoTranslatorGemini, SGRAutoTranslatorClaude, SGRAutoTranslatorOpenAI, SGRAutoTranslatorCount
};
typedef NS_ENUM(NSInteger, SGRAutoTranslationState) {
    SGRAutoTranslationReady, SGRAutoTranslationNeedsKey, SGRAutoTranslationNeedsSwitch,
    SGRAutoTranslationNeedsSettings, SGRAutoTranslationUnavailableDevice, SGRAutoTranslationUnsupportedLanguage
};
BOOL SGRAutoTranslationEnabled(void);
NSArray<NSNumber *> *SGRAutoTranslationOrder(void);
void SGRSetAutoTranslationOrder(NSArray<NSNumber *> *order);
SGRAutoTranslationState SGRAutoTranslationStateOf(SGRAutoTranslator provider, NSString *language);
BOOL SGRAutoTranslationAvailable(SGRAutoTranslator provider, NSString *language);
SGModRow *SGRAutoTranslationRow(void);
SGModRow *SGRAutoTranslationOrderRow(void);
// Explicit toggle/order change: cancel old automatic jobs, allow attempts again, notify views.
void SGRAutoTranslationSettingsChanged(void);
extern NSNotificationName const SGRAutoTranslationDidChangeNotification;
// Main-thread session ledger shared by all lyric views. Zero means already tried or manually suppressed.
NSUInteger SGRAutoTranslationRevision(void);
NSUInteger SGRAutoTranslationClaim(NSString *track, NSString *language);
void SGRAutoTranslationSuppress(NSString *track, NSString *language);
void SGRAutoTranslationRegister(NSString *track, NSString *language, NSUInteger token);
void SGRAutoTranslationFinish(NSString *track, NSString *language, NSUInteger token);
typedef void (^SGRAutoTranslated)(NSArray<NSString *> *lines, NSString *error);
void SGRAutoTranslateInOrder(NSArray<SGKaraokeLine *> *lines, NSString *track, NSString *language,
                             NSUInteger revision, BOOL (^mayContinue)(void), SGRAutoTranslated progress, SGRAutoTranslated done);

// Main-thread snapshots for the current song, never persisted or attributed to restored cache entries.
typedef NS_ENUM(NSInteger, SGRAutoTranslationPhase) {
    SGRAutoTranslationPhaseRunning, SGRAutoTranslationPhaseComplete, SGRAutoTranslationPhasePartial,
    SGRAutoTranslationPhaseFailed, SGRAutoTranslationPhaseUnavailable, SGRAutoTranslationPhasePaused
};
typedef NS_ENUM(NSInteger, SGRAutoTranslationFailure) {
    SGRAutoTranslationFailureNone, SGRAutoTranslationFailureConnection,
    SGRAutoTranslationFailureAuthentication, SGRAutoTranslationFailureBusy, SGRAutoTranslationFailureResponse
};
@interface SGRAutoTranslationProgress : NSObject
@property (nonatomic, readonly) SGRAutoTranslationPhase phase;
@property (nonatomic, readonly) SGRAutoTranslator provider;
@property (nonatomic, readonly) SGRAutoTranslationFailure failure;
@property (nonatomic, readonly) NSUInteger completed, total, attempt;
@end
extern NSNotificationName const SGRAutoTranslationProgressDidChangeNotification; // track or nil after reset; language in userInfo
SGRAutoTranslationProgress *SGRAutoTranslationProgressFor(NSString *track, NSString *language);
// A user-requested retry clears only this pair's terminal status/attempt; never starts networking itself.
BOOL SGRAutoTranslationRetry(NSString *track, NSString *language);
// Report this only when eligible untranslated lyrics have no available service. Consumes no attempt.
void SGRAutoTranslationUnavailable(NSString *track, NSString *language);
