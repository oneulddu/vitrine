// Shared request builders and bounded reply checks, also exercised by the offline harness.
#import "LyricsTranslation.h"

NSArray<NSString *> *SGLyricsAIArrayIn(id content, NSUInteger count);
NSString *SGLyricsTranslationInstruction(void);
NSString *SGLyricsTranslationPrompt(NSArray<NSString *> *texts, NSString *languageTag);
NSArray<NSString *> *SGLyricsAITexts(NSArray<SGKaraokeLine *> *lines);
NSString *SGLyricsAIJobPrompt(NSString *kind, NSArray<NSString *> *texts, NSString *languageTag, NSInteger notation);
NSArray<NSString *> *SGLyricsAIJobReply(NSString *kind, NSArray<NSString *> *texts, NSArray<NSString *> *answer);
NSArray<NSDictionary<NSString *, NSString *> *> *SGOpenAIPresets(void);
NSString *SGOpenAIPresetName(void);
// Pure host/account and migration decisions. A missing base means the default OpenAI address;
// an invalid one defers migration. An existing host key always wins over the legacy item.
NSString *SGOpenAIKeyHost(NSString *base);
typedef NS_ENUM(NSInteger, SGOpenAIKeyMigration) {
    SGOpenAIKeyMigrationNone, SGOpenAIKeyMigrationDeferred,
    SGOpenAIKeyMigrationCopy, SGOpenAIKeyMigrationDeleteLegacy
};
SGOpenAIKeyMigration SGOpenAIKeyMigrationDecision(NSString *base, BOOL legacyExists, BOOL hostKeyExists);
NSURLRequest *SGOpenAIRequest(NSString *system, NSString *prompt, NSString **problem);
NSURLRequest *SGClaudeRequest(NSString *system, NSString *prompt, NSString **problem);
NSURLRequest *SGGeminiAIRequest(NSString *system, NSString *prompt, NSString **problem);
NSArray<NSString *> *SGClaudeTranslationsIn(id root, NSInteger status, NSError *error, NSUInteger count, NSString **problem);
void SGLyricsAIAsk(SGLyricsAI service, NSString *system, NSString *prompt, NSUInteger count,
                   void (^done)(NSArray<NSString *> *, NSString *));
BOOL SGLyricsTitleNeedsTranslation(NSString *title, NSString *languageTag);
BOOL SGLyricsTitleLatinArtist(NSString *artist);

void SGLyricsAIForgotten(void);
void SGLyricsDeleteSavedTranslations(void);
