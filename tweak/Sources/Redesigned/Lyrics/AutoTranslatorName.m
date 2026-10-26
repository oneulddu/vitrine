#import "Core/SGLocalize.h"
#import "AutoTranslation.h"

NSString *SGRAutoTranslatorName(SGRAutoTranslator provider) {
    switch (provider) {
        case SGRAutoTranslatorOnDevice: return SGL(@"settings.lyrics.auto_translation.ondevice", @"Apple Translate");
        case SGRAutoTranslatorAppleIntelligence: return SGL(@"settings.lyrics.auto_translation.intelligence", @"Apple Intelligence");
        case SGRAutoTranslatorGoogle: return SGL(@"settings.translation.google.title", @"Google Translate");
        case SGRAutoTranslatorBing: return SGL(@"settings.translation.bing.title", @"Bing Translator");
        case SGRAutoTranslatorDeepL: return SGL(@"settings.lyrics.auto_translation.deepl", @"DeepL");
        case SGRAutoTranslatorGemini: return SGL(@"settings.lyrics.auto_translation.gemini", @"Gemini");
        case SGRAutoTranslatorClaude: return SGL(@"settings.lyrics.auto_translation.claude", @"Claude");
        case SGRAutoTranslatorOpenAI: return SGL(@"settings.lyrics.auto_translation.openai", @"Your AI service");
        default: return nil;
    }
}
