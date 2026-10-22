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

// One bounded/cancellable attempt for an explicit connection test; unlike translation jobs, no retry.
NSURLSessionDataTask *SGLyricsTranslationSendOnce(NSURLRequest *request, void (^finished)(NSData *, NSInteger, NSError *));
// The same with its own reply size limit in bytes, for a model list (OpenRouter's runs past 512 KiB).
NSURLSessionDataTask *SGLyricsTranslationSendOnceUpTo(NSURLRequest *request, NSUInteger limit, void (^finished)(NSData *, NSInteger, NSError *));

// A model-list failure that never reached the service, told apart from a reply: an ATS refusal, an
// unresolvable host, nothing listening, a timeout or no network each get their own sentence. The
// error is logged by its domain and code only, never with the request or its credentials.
NSString *SGLyricsAIConnectionProblem(NSError *error);
// Model names as a service takes them: trimmed, 1-256 characters, no control characters; else nil.
NSString *SGLyricsAICleanModel(NSString *text);
// Each service's model in use: the stored one when it is clean, else the service's default.
NSString *SGGeminiModel(void);
NSString *SGClaudeModel(void);
NSString *SGOpenAIModel(void);
// GET requests for the service's model list with the saved key (and address), or nil and why not.
NSURLRequest *SGGeminiModelsRequest(NSString **problem);
NSURLRequest *SGClaudeModelsRequest(NSString **problem);
NSURLRequest *SGOpenAIModelsRequest(NSString **problem);
// The OpenAI-compatible base URL's /models, under the same rules as SGOpenAICompletionURL; else nil.
NSURL *SGOpenAIModelsURL(NSString *base);
// A model list reply read: @{@"id", optional @"name"} each, deduplicated, at most 2000. Gemini's keeps only
// models that generate content, without the "models/" prefix; OpenAI-compatible lists are sorted by ID.
// Nil for a reply that is not a list.
NSArray<NSDictionary<NSString *, NSString *> *> *SGLyricsAIModelsIn(SGLyricsAI service, id root);
