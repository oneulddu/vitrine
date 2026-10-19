// Asserts the lyrics PiP text decision offline: what current/next a frame shows for nil, empty,
// untimed and timed lines, at positions taken from SGKaraokeLeadLine's rule in KaraokeTiming.m.
// Exits 1 on any failure.
#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import "Shared/LyricsPiP/LyricsPiPText.h"
#import "Shared/LyricsPiP/LyricsPiPFrame.h"

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

static void fitCheck(NSString *what, NSString *text, CGRect rect, CGFloat size, CGFloat minSize,
                     CGFloat wantSize, NSUInteger wantLines, BOOL wantTruncated) {
    SGLyricsPiPTextFit fit = SGLyricsPiPFitText(text, rect.size, size, minSize);
    checks++;
    BOOL ok = fit.size == wantSize && fit.lines == wantLines && fit.truncated == wantTruncated;
    if (!ok) {
        failures++;
        printf("FAIL %s: size %.1f lines %lu truncated %d, wanted size %.1f lines %lu truncated %d\n",
               what.UTF8String, fit.size, (unsigned long)fit.lines, fit.truncated,
               wantSize, (unsigned long)wantLines, wantTruncated);
    }
    printf("  %s: size %.1f, %lu lines, %s\n", what.UTF8String, fit.size,
           (unsigned long)fit.lines, fit.truncated ? "truncated" : "not truncated");
}

static NSString *words(NSUInteger count) {
    NSMutableArray<NSString *> *all = [NSMutableArray array];
    NSArray<NSString *> *pool = @[@"every", @"word", @"fits", @"inside", @"a", @"frame", @"that", @"the",
                                  @"phone", @"draws", @"while", @"lyrics", @"keep", @"coming"];
    for (NSUInteger i = 0; i < count; i++) [all addObject:pool[i % pool.count]];
    return [all componentsJoinedByString:@" "];
}

static void writeFrame(NSString *directory, NSString *name, NSArray<NSString *> *content) {
    NSData *png = SGLyricsPiPFramePNG(content);
    checks++;
    if (!png.length) {
        failures++;
        printf("FAIL %s: no PNG data\n", name.UTF8String);
        return;
    }
    NSString *path = [directory stringByAppendingPathComponent:[name stringByAppendingString:@".png"]];
    if (![png writeToFile:path atomically:YES]) {
        failures++;
        printf("FAIL %s: the PNG could not be written\n", path.UTF8String);
        return;
    }
    printf("  frame: %s (%lu bytes)\n", path.UTF8String, (unsigned long)png.length);
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

        // Frame fitting, with the real rects and sizes of LyricsPiPFrame.m.
        CGRect current = CGRectMake(24, 156, 592, 180);
        CGRect credit = CGRectMake(24, 10, 592, 58);
        fitCheck(@"short current text fits at the start size", @"One short line", current, 40, 24, 40, 1, NO);
        // Enough for four lines at 40pt, but fewer at a smaller size: it shrinks, still in full.
        NSString *medium = @"We were dancing in the kitchen light and every word you said "
            @"hung in the air like smoke until the morning came and took it all away again";
        SGLyricsPiPTextFit mediumFit = SGLyricsPiPFitText(medium, current.size, 40, 24);
        printf("  medium: size %.1f, %lu lines, %s\n", mediumFit.size,
               (unsigned long)mediumFit.lines, mediumFit.truncated ? "truncated" : "not truncated");
        checks++;
        if (!(mediumFit.size > 24 && mediumFit.size < 40 && !mediumFit.truncated && mediumFit.lines >= 1)) {
            failures++;
            printf("FAIL medium: size %.1f is not inside (24, 40) or it truncated\n", mediumFit.size);
        }
        NSString *longCredit = words(110);
        SGLyricsPiPTextFit longFit = SGLyricsPiPFitText(longCredit, credit.size, 17, 12);
        CTFontRef font = CTFontCreateWithName(CFSTR("HelveticaNeue"), longFit.size, NULL);
        CGFloat lineHeight = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font);
        CFRelease(font);
        checks++;
        BOOL longOk = longFit.size == 12 && longFit.truncated && longFit.lines >= 1 &&
            longFit.lines * lineHeight <= credit.size.height;
        if (!longOk) {
            failures++;
            printf("FAIL long credit: size %.1f lines %lu truncated %d, height %.1f > %.1f\n",
                   longFit.size, (unsigned long)longFit.lines, longFit.truncated,
                   longFit.lines * lineHeight, credit.size.height);
        }
        printf("  long credit: size %.1f, %lu lines, %s, %.1f pt of 58\n", longFit.size,
               (unsigned long)longFit.lines, longFit.truncated ? "truncated" : "not truncated",
               longFit.lines * lineHeight);
        fitCheck(@"empty text draws nothing", @"", current, 40, 24, 40, 0, NO);
        // Hard breaks past the box: as many 12pt lines as the long credit, still cut (the frame PNG shows the "…").
        NSMutableArray<NSString *> *rows = [NSMutableArray array];
        for (int i = 0; i < 12; i++) [rows addObject:@"A"];
        NSString *hardBreaks = [rows componentsJoinedByString:@"\n"];
        fitCheck(@"hard breaks past the box", hardBreaks, credit, 17, 12, 12, longFit.lines, YES);
        fitCheck(@"a box too short for one line", @"Too tall", CGRectMake(0, 0, 592, 5), 17, 12, 12, 0, NO);

        NSFileManager *files = NSFileManager.defaultManager;
        // The executable sits in build/, so the frames go beside it at build/frames whatever the cwd.
        NSString *frames = [[[NSProcessInfo processInfo].arguments[0] stringByDeletingLastPathComponent]
            stringByAppendingPathComponent:@"frames"];
        [files createDirectoryAtPath:frames withIntermediateDirectories:YES attributes:nil error:NULL];
        writeFrame(frames, @"short", @[@"One short line", @"The next one", @"Lyrics by Someone"]);
        writeFrame(frames, @"long", @[medium, @"The next one", @"Lyrics by Someone"]);
        writeFrame(frames, @"long-credit", @[@"One short line", @"The next one", longCredit]);
        writeFrame(frames, @"hard-breaks", @[@"One short line", @"The next one", hardBreaks]);
        writeFrame(frames, @"instrumental",@[@"Instrumental", @"And the next line comes", @"Lyrics by Someone"]);
    }
    if (failures) {
        printf("lyrics-pip: %d of %d checks failed\n", failures, checks);
        return 1;
    }
    printf("lyrics-pip: all %d checks passed\n", checks);
    return 0;
}
