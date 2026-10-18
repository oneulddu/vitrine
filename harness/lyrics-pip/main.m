// Asserts the lyrics PiP text decision offline: what current/next a frame shows for nil, empty,
// untimed and timed lines, at positions taken from SGKaraokeLeadLine's rule in KaraokeTiming.m.
// Exits 1 on any failure.
#import <Foundation/Foundation.h>
#import "Shared/LyricsPiP/LyricsPiPText.h"

static int failures, checks;

static SGKaraokeLine *line(NSString *text, NSInteger start, NSInteger end, SGKaraokeTiming timing) {
    SGKaraokeWord *word = [SGKaraokeWord new];
    word.text = text;
    word.start = start;
    word.end = end;
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.words = @[word];
    line.start = start;
    line.end = end;
    line.timing = timing;
    return line;
}

static void check(NSString *what, NSArray<SGKaraokeLine *> *lines, NSInteger positionMs,
                  SGLyricsPiPTextKind kind, NSString *current, NSString *next) {
    NSString *gotCurrent = nil, *gotNext = nil;
    SGLyricsPiPTextKind got = SGLyricsPiPTextFor(lines, positionMs, &gotCurrent, &gotNext);
    checks++;
    BOOL ok = got == kind && [gotCurrent isEqualToString:current] && [gotNext isEqualToString:next];
    if (!ok) {
        failures++;
        printf("FAIL %s: kind %ld current \"%s\" next \"%s\", wanted kind %ld current \"%s\" next \"%s\"\n",
               what.UTF8String, (long)got, gotCurrent.UTF8String, gotNext.UTF8String,
               (long)kind, current.UTF8String, next.UTF8String);
    }
}

int main(void) {
    @autoreleasepool {
        // nil: the track has no lyrics yet.
        check(@"nil lines", nil, 0, SGLyricsPiPTextNoLyrics, @"", @"");

        // An empty array is the source saying the track is instrumental.
        check(@"empty lines", @[], 0, SGLyricsPiPTextInstrumental, @"", @"");

        // Plain text: no offset anywhere, so it is untimed whatever its timing says.
        NSArray *untimed = @[line(@"One", 0, 0, SGKaraokeTimingNone),
                             line(@"Two", 0, 0, SGKaraokeTimingNone)];
        check(@"untimed lines", untimed, 5000, SGLyricsPiPTextUntimed, @"One", @"");

        // Line-timed: lyrics [One 1000-2000], [Two 3000-4000].
        NSArray *timed = @[line(@"One", 1000, 2000, SGKaraokeTimingLine),
                           line(@"Two", 3000, 4000, SGKaraokeTimingLine)];
        // Before the first line. LeadLine is -1; the old image's "♪" fallback makes it Instrumental,
        // with the first line as next.
        check(@"before first line", timed, 500, SGLyricsPiPTextInstrumental, @"", @"One");
        check(@"at first line", timed, 1000, SGLyricsPiPTextLine, @"One", @"Two");
        check(@"middle of a line", timed, 1500, SGLyricsPiPTextLine, @"One", @"Two");
        // Between lines LeadLine keeps the last one begun: the previous line stays up.
        check(@"between two lines", timed, 2500, SGLyricsPiPTextLine, @"One", @"Two");
        // After the last line a line-timed line is not dropped: only word-timed ends cut it.
        check(@"after last line", timed, 5000, SGLyricsPiPTextLine, @"Two", @"");

        // Word-timed words [One 1000-2000], then [Two 3000-4000]. Past the last word's end the line
        // is finished: Instrumental, with the following line as next.
        NSArray *wordTimed = @[line(@"One", 1000, 2000, SGKaraokeTimingWords),
                               line(@"Two", 3000, 4000, SGKaraokeTimingWords)];
        check(@"word-timed line finished", wordTimed, 2500, SGLyricsPiPTextInstrumental, @"", @"Two");
        check(@"word-timed line singing", wordTimed, 1500, SGLyricsPiPTextLine, @"One", @"Two");

        // A timed line whose text is empty or the break glyph shows Instrumental.
        check(@"empty timed text", @[line(@"", 1000, 2000, SGKaraokeTimingLine)], 1500,
              SGLyricsPiPTextInstrumental, @"", @"");
        check(@"♪ timed text", @[line(@"♪", 1000, 2000, SGKaraokeTimingLine)], 1500,
              SGLyricsPiPTextInstrumental, @"", @"");

        // The last timed line finished with nothing after it: Instrumental, empty next.
        check(@"last word-timed line finished", @[line(@"One", 1000, 2000, SGKaraokeTimingWords)], 2500,
              SGLyricsPiPTextInstrumental, @"", @"");
    }
    if (failures) {
        printf("lyrics-pip: %d of %d checks failed\n", failures, checks);
        return 1;
    }
    printf("lyrics-pip: all %d checks passed\n", checks);
    return 0;
}
