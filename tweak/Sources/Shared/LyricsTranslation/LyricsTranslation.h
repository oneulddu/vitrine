// A song's lines translated into any language by Gemini, on the user's own API key, at a tap in the
// lyrics' corner menu. The key lives in the Keychain, not in the settings, so a settings export never
// carries it. Only the lyrics' text and the language go out, to Google's Gemini API.
#import <UIKit/UIKit.h>

@class SGKaraokeLine, SGModRow;

BOOL SGGeminiKeySet(void);

// Posted on the main thread when the saved translations are deleted or Translate any song changes: the lyrics
// page syncs its song again and redraws.
extern NSNotificationName const SGLyricsTranslationsDidChangeNotification;

// On: the translate menu is offered for every song, not only those found in another language.
#define SGKeyLyricsTranslateEverySong @"spotifyglass.lyrics.translateEverySong"
SGModRow *SGTranslateEverySongRow(void);

// One translation per line, in order, or nil and a message to show. Main queue. The same song in the
// same language is asked once a launch.
void SGLyricsTranslateWithGemini(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                                 void (^done)(NSArray<NSString *> *translations, NSString *error));

// "“Title” by Artist" for a track the player or the local files know, for a translator's instructions; else nil.
NSString *SGLyricsSongName(NSString *trackID);

// The language a translation is asked in: the Lyrics page's, else the phone's own.
NSString *SGLyricsGeminiLanguage(void);

// Gemini's reply read: one translation per line when it has exactly `count`, else nil and in `problem`
// why not (the key, the limit, a filter, a recitation stop, a line count that does not match).
NSArray<NSString *> *SGGeminiTranslationsIn(id root, NSInteger status, NSError *error, NSUInteger count, NSString **problem);

// The Lyrics page's row: shows whether a key is set, and sets or removes it.
SGModRow *SGGeminiKeyRow(void);

// On the iPhone itself (OnDeviceTranslation.swift): Apple's Translate, with both languages downloaded in the
// Translate app, and Apple Intelligence's model. Each gives one translation per line ("" for a line with no
// words), or nil and a message to show, on the main queue.
@interface SGOnDeviceTranslation : NSObject
@property (class, readonly) BOOL translationAvailable;
+ (BOOL)appleIntelligenceAvailable:(NSString *)languageTag;
+ (void)translate:(NSArray<NSString *> *)lines to:(NSString *)languageTag done:(void (^)(NSArray<NSString *> *lines, NSString *error))done;
// Apple Intelligence works through the song a batch at a time: `progress` gets the lines so far, "" for the rest.
+ (void)translateWithAppleIntelligence:(NSArray<NSString *> *)lines to:(NSString *)languageTag song:(NSString *)song
                              progress:(void (^)(NSArray<NSString *> *lines))progress
                                  done:(void (^)(NSArray<NSString *> *lines, NSString *error))done;
@end

// SavedTranslations.m: a song's translations kept on disk by track and language, matched to lines by their text.
// The saved ones are the truth for translations made here: syncing fills the lines with no translation from them,
// and takes a made translation off a line that has none saved (after Delete). Main thread.
void SGLyricsSyncSavedTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines);
void SGLyricsSaveTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines);
// The Lyrics page's row: how many songs are kept, and a tap to delete them.
SGModRow *SGSavedTranslationsRow(void);

// Other services for the same menu. Keys stay in the Keychain; Google requires its own opt-in switch.
BOOL SGDeepLKeySet(void);
SGModRow *SGDeepLKeyRow(void);
#define SGKeyLyricsGoogleTranslate @"spotifyglass.lyrics.googleTranslate"
SGModRow *SGGoogleTranslateRow(void);
void SGLyricsTranslateWithDeepL(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                               void (^done)(NSArray<NSString *> *translations, NSString *error));
void SGLyricsTranslateWithGoogle(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                                void (^done)(NSArray<NSString *> *translations, NSString *error));

#define SGKeyLyricsOpenAIBaseURL @"spotifyglass.lyrics.openai.baseURL"
#define SGKeyLyricsOpenAIModel @"spotifyglass.lyrics.openai.model"
BOOL SGOpenAIKeySet(void);
SGModRow *SGOpenAIKeyRow(void);
void SGLyricsTranslateWithOpenAI(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                                void (^done)(NSArray<NSString *> *translations, NSString *error));

// Pure checks shared with harness/lyrics-translation. Batches contain original line indices, skip blank
// lines and include joined newlines in their character limit. Invalid or oversized input returns nil.
NSString *SGDeepLTargetLanguage(NSString *tag);
NSArray<NSString *> *SGDeepLTranslationsIn(id root, NSUInteger count);
NSArray<NSArray<NSNumber *> *> *SGLyricsTranslationBatches(NSArray<NSString *> *texts, NSUInteger maxLines, NSUInteger maxCharacters);
NSString *SGGoogleTargetLanguage(NSString *tag);
BOOL SGGoogleKeepsLine(NSString *text);
NSString *SGGoogleTranslationTextIn(id root);
NSArray<NSString *> *SGGoogleTranslationLinesIn(id root, NSUInteger count);
NSData *SGGoogleTranslationForm(NSString *text, NSString *languageTag);
NSURL *SGOpenAICompletionURL(NSString *base);
NSArray<NSString *> *SGOpenAITranslationsIn(id root, NSUInteger count);

// The translators' bounded, ephemeral transport, implemented in DeepL.m. Call on main; completion is
// on main too. Retries 429 three times, and 5xx when asked. `allowed` is checked before every attempt.
void SGLyricsTranslationSendRequest(NSURLRequest *request, BOOL retryServer, BOOL (^allowed)(void),
                                   void (^finished)(NSData *data, NSInteger status, NSError *error));

#define SGKeyLyricsBingTranslate @"spotifyglass.lyrics.bingTranslate"   // off until switched on
SGModRow *SGBingTranslateRow(void);
void SGLyricsTranslateWithBing(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag, void (^done)(NSArray<NSString *> *translations, NSString *error));
NSString *SGBingTargetLanguage(NSString *tag);
NSDictionary *SGBingConfigurationIn(NSString *html);
NSString *SGBingTranslationTextIn(id root);
BOOL SGBingTokenRefused(id root);
