// Included by translation-check.m. How the real line view wraps its words into rows: a word timed syllable by
// syllable (the items after the first joined) is never split across two rows unless it is wider than a row.
// Widths are measured from the style's own font, so the rows below hold at any font; a line view is made
// as wide as the row each case wants.

static SGKaraokeLine *wrapLine(NSArray<NSString *> *texts, NSIndexSet *joined) {
    NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
    NSInteger at = 0;
    for (NSUInteger i = 0; i < texts.count; i++) {
        SGKaraokeWord *word = [SGKaraokeWord new];
        word.text = texts[i];
        word.joined = [joined containsIndex:i];
        word.start = at;
        word.end = at + 200;
        at += 200;
        [words addObject:word];
    }
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.words = words;
    line.start = 0;
    line.end = at;
    line.timing = SGKaraokeTimingWords;
    return line;
}

static CGFloat wrapWide(NSString *text, UIFont *font) {
    return ceil([text sizeWithAttributes:@{NSFontAttributeName: font}].width);
}

// The rows and sweep offsets the line view gives each word, as the row's index by the word view's centre.
static void wrapPlaces(NSArray<NSString *> *texts, NSIndexSet *joined, CGFloat width, id style, NSArray<NSNumber *> **rows, NSArray<NSNumber *> **offsets) {
    UIView *lineView = ((id (*)(id, SEL, id, CGFloat, id, id, BOOL, BOOL))objc_msgSend)([NSClassFromString(@"SGRKaraokeLineView") alloc],
        NSSelectorFromString(@"initWithLine:width:style:under:blurred:sweepsEstimates:"), wrapLine(texts, joined), width, style, nil, NO, NO);
    NSMutableArray<NSNumber *> *ys = [NSMutableArray array], *found = [NSMutableArray array], *sweep = [NSMutableArray array];
    for (UIView *word in [lineView valueForKey:@"words"]) {
        if (![ys containsObject:@(word.center.y)]) [ys addObject:@(word.center.y)];
    }
    [ys sortUsingSelector:@selector(compare:)];
    for (UIView *word in [lineView valueForKey:@"words"]) {
        [found addObject:@([ys indexOfObject:@(word.center.y)])];
        [sweep addObject:[word valueForKey:@"offset"]];
    }
    *rows = found;
    *offsets = sweep;
}

static void wrapChecks(void) {
    id style = ((id (*)(id, SEL, CGFloat, NSArray *, BOOL, BOOL, BOOL))objc_msgSend)([NSClassFromString(@"SGRKaraokeStyle") alloc],
        NSSelectorFromString(@"initWithSize:order:pronunciation:translation:romanised:"), 30, SGRLyricsTextOrder(), NO, NO, NO);
    UIFont *font = [style valueForKey:@"lyrics"];
    CGFloat space = wrapWide(@" ", font);
    NSArray<NSNumber *> *rows, *offsets;

    // One syllable still fits where its row ends and the next does not: "cra" + "zy" goes down whole, "one two" stays.
    CGFloat edge = wrapWide(@"one", font) + space + wrapWide(@"two", font) + space + wrapWide(@"cra", font) + wrapWide(@"zy", font) - 1;
    wrapPlaces(@[@"one", @"two", @"cra", @"zy"], [NSIndexSet indexSetWithIndex:3], edge, style, &rows, &offsets);
    check([rows isEqualToArray:@[@0, @0, @1, @1]], [NSString stringWithFormat:@"a syllable run at the row's edge goes down whole: rows %@", [rows componentsJoinedByString:@","]]);
    CGFloat two = wrapWide(@"one", font) + space, run = two + wrapWide(@"two", font);
    check(offsets.count == 4 && fabs(offsets[2].doubleValue - run) < 0.01 && fabs(offsets[3].doubleValue - (run + wrapWide(@"cra", font))) < 0.01,
          [NSString stringWithFormat:@"the moved run's sweep offsets follow the row before it: %@", [offsets componentsJoinedByString:@","]]);

    // A run wider than a row is broken inside, where it does not fit.
    CGFloat wide = wrapWide(@"mmmm", font);
    wrapPlaces(@[@"a", @"mmmm", @"mmmm", @"mmmm"], [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(2, 2)], 2 * wide + 1, style, &rows, &offsets);
    check([rows isEqualToArray:@[@0, @0, @1, @1]], [NSString stringWithFormat:@"a run wider than a row breaks inside: rows %@", [rows componentsJoinedByString:@","]]);

    // A line of an unspaced script, every item joined to the one before, wraps at the row's width.
    CGFloat kana = wrapWide(@"あ", font);
    wrapPlaces(@[@"あ", @"あ", @"あ", @"あ", @"あ", @"あ", @"あ", @"あ"], [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 7)], 3 * kana + 1, style, &rows, &offsets);
    check([rows isEqualToArray:@[@0, @0, @0, @1, @1, @1, @2, @2]], [NSString stringWithFormat:@"a fully joined line wraps: rows %@", [rows componentsJoinedByString:@","]]);

    // Words with nothing joined wrap one by one, as before.
    wrapPlaces(@[@"mmmm", @"mmmm", @"mmmm", @"mmmm"], [NSIndexSet indexSet], 2 * wide + space + 1, style, &rows, &offsets);
    check([rows isEqualToArray:@[@0, @0, @1, @1]], [NSString stringWithFormat:@"words that are not joined wrap as before: rows %@", [rows componentsJoinedByString:@","]]);
}
