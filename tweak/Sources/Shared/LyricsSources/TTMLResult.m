#import "LyricsSources.h"

// Keep the provider adapter separate from the standalone TTML parser.
SGLyricsResult *SGTTMLResult(NSString *xml, BOOL wordTimed) {
    NSArray<SGKaraokeLine *> *lines = SGTTMLLines(xml);
    if (!lines) return nil;
    SGLyricsResult *result = [SGLyricsResult new];
    result.synced = YES;
    result.wordTimed = wordTimed;
    result.karaokeLines = lines;
    NSArray<NSNumber *> *starts;
    NSArray<NSString *> *texts;
    SGLyricsPageLines(lines, &starts, &texts);
    result.starts = starts;
    result.texts = texts;
    return result;
}
