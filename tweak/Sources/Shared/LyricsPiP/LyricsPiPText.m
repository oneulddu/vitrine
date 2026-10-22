#import "LyricsPiPText.h"

SGLyricsPiPTextKind SGLyricsPiPTextFor(NSArray<SGKaraokeLine *> *lines, NSInteger positionMs,
                                       NSString **current, NSString **next) {
    SGLyricsPiPTextKind kind = SGLyricsPiPTextNoLyrics;
    NSString *shown = @"", *following = @"";
    if (lines && !lines.count) {
        kind = SGLyricsPiPTextInstrumental;
    } else if (lines.count) {
        BOOL timed = NO;
        for (SGKaraokeLine *line in lines) {
            if (line.start > 0 || line.end > 0) { timed = YES; break; }
        }
        if (!timed || SGKaraokeLinesTiming(lines) == SGKaraokeTimingNone) {
            kind = SGLyricsPiPTextUntimed;
            shown = SGKaraokeLineText(lines.firstObject);
        } else {
            NSInteger index = SGKaraokeLeadLine(lines, positionMs);
            SGKaraokeLine *line = index >= 0 ? lines[index] : nil;
            // LeadLine keeps the last line between verses and after the song's final lyric. Only a word-timed
            // line's end is the source's; a line-timed one's is an estimate (KaraokeTiming.m timedLine) that
            // can run out mid-note, and its breaks come as their own empty or ♪ lines.
            NSInteger end = MAX(line.end, line.words.lastObject.end);
            BOOL over = line.timing == SGKaraokeTimingWords && positionMs > end;
            NSString *text = line && !over ? SGKaraokeLineText(line) : @"♪";
            if (index + 1 < (NSInteger)lines.count) following = SGKaraokeLineText(lines[index + 1]);
            if (!text.length || [text isEqualToString:@"♪"]) {
                kind = SGLyricsPiPTextInstrumental;
            } else {
                kind = SGLyricsPiPTextLine;
                shown = text;
            }
        }
    }
    if (current) *current = shown ?: @"";
    if (next) *next = following ?: @"";
    return kind;
}

SGKaraokeLine *SGLyricsPiPSelectedLine(NSArray<SGKaraokeLine *> *lines, NSInteger positionMs) {
    SGLyricsPiPTextKind kind = SGLyricsPiPTextFor(lines, positionMs, NULL, NULL);
    if (kind == SGLyricsPiPTextUntimed) return lines.firstObject;
    if (kind != SGLyricsPiPTextLine) return nil;
    NSInteger index = SGKaraokeLeadLine(lines, positionMs);
    return index >= 0 ? lines[index] : nil;
}
