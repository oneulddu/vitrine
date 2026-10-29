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

static UIView *wrapView(SGKaraokeLine *line, CGFloat width, id style) {
    return ((id (*)(id, SEL, id, CGFloat, id, id, BOOL, BOOL))objc_msgSend)([NSClassFromString(@"SGRKaraokeLineView") alloc],
        NSSelectorFromString(@"initWithLine:width:style:under:blurred:sweepsEstimates:"), line, width, style, nil, NO, NO);
}

static void wrapExtras(id style, SGKaraokeLine *line, NSArray<SGLyricsRuby *> *ruby, NSString *reading) {
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    NSUInteger start = 0;
    for (SGKaraokeWord *word in line.words) {
        if (start && !word.joined) start++;
        [ranges addObject:[NSValue valueWithRange:NSMakeRange(start, word.text.length)]];
        start += word.text.length;
    }
    SGKaraokeLine *spoken = reading ? wrapLine(@[reading], NSIndexSet.indexSet) : nil;
    SGLyricsPreparedExtras *extras = ((id (*)(id, SEL, id, id, id, id))objc_msgSend)([SGLyricsPreparedExtras alloc],
        NSSelectorFromString(@"initWithPronunciation:ranges:wordRanges:ruby:"), spoken,
        spoken ? @[[NSValue valueWithRange:NSMakeRange(0, start)]] : @[], ranges, ruby);
    [style setValue:@{line.words: extras} forKey:@"extras"];
}

static void wrapRubyCheck(id style, NSArray<NSString *> *texts, CGFloat width, NSString *reading,
                          NSArray<NSString *> *expected, NSArray<NSNumber *> *anchors, BOOL right) {
    SGKaraokeLine *line = wrapLine(texts, [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, texts.count - 1)]);
    if (right) line.align = SGKaraokeAlignTrailing;
    SGLyricsRuby *ruby = [SGLyricsRuby new];
    ruby.range = NSMakeRange(0, SGKaraokeLineText(line).length);
    ruby.reading = reading;
    wrapExtras(style, line, @[ruby], nil);
    UIView *view = wrapView(line, width, style);
    NSArray<UILabel *> *labels = [view valueForKey:@"furigana"];
    NSArray<UIView *> *words = [view valueForKey:@"lyricWords"];
    check([[labels valueForKey:@"text"] isEqual:expected],
        [NSString stringWithFormat:@"wrapped ruby preserves whole reading graphemes: %@", expected]);
    BOOL placed = labels.count == anchors.count;
    for (NSUInteger i = 0; i < MIN(labels.count, anchors.count); i++) {
        CGRect frame = [labels[i] convertRect:labels[i].bounds toView:view];
        CGRect word = words[anchors[i].unsignedIntegerValue].frame;
        placed &= fabs(CGRectGetMaxY(frame) - CGRectGetMinY(word)) < 0.01 &&
            CGRectGetMinX(frame) >= -0.01 && CGRectGetMaxX(frame) <= width + 0.01;
    }
    check(placed, @"every ruby fragment is above its own row and inside that row's horizontal bounds");
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

    [style setValue:[UIFont systemFontOfSize:12] forKey:@"furigana"];
    CGFloat han = wrapWide(@"甲", font), edgeTwo = 2 * han + 1;
    wrapRubyCheck(style, @[@"甲", @"乙", @"丙", @"丁"], edgeTwo, @"か\u3099きくけ",
        @[@"か\u3099き", @"くけ"], @[@0, @2], NO);
    wrapRubyCheck(style, @[@"甲", @"乙", @"丙"], han + 1, @"あいうえおか",
        @[@"あい", @"うえ", @"おか"], @[@0, @1, @2], YES);
    wrapRubyCheck(style, @[@"𠮷", @"野", @"家"], wrapWide(@"𠮷", font) + wrapWide(@"野", font) + 1,
        @"よしのや", @[@"よしの", @"や"], @[@0, @2], NO);
    wrapRubyCheck(style, @[@"甲", @"乙"], edgeTwo, @"あいうえおかきくけこさしすせそたちつてとなにぬねの",
        @[@"あいうえおかきくけこさしすせそたちつてとなにぬねの"], @[@0], NO);

    // A known per-character reading is authoritative; do not redistribute it over the compound.
    SGKaraokeLine *known = wrapLine(@[@"甲", @"乙"], [NSIndexSet indexSetWithIndex:1]);
    SGLyricsRuby *first = [SGLyricsRuby new], *second = [SGLyricsRuby new];
    first.range = NSMakeRange(0, 1); first.reading = @"こう";
    second.range = NSMakeRange(1, 1); second.reading = @"おつ";
    wrapExtras(style, known, @[first, second], nil);
    UIView *knownView = wrapView(known, han + 1, style);
    check([[[knownView valueForKey:@"furigana"] valueForKey:@"text"] isEqual:@[@"こう", @"おつ"]],
          @"known character readings remain intact across rows");

    // Generated pronunciation uses the same source-row boundaries, not just the first source word.
    id paired = ((id (*)(id, SEL, CGFloat, NSArray *, BOOL, BOOL, BOOL))objc_msgSend)([NSClassFromString(@"SGRKaraokeStyle") alloc],
        NSSelectorFromString(@"initWithSize:order:pronunciation:translation:romanised:"), 30, @[@0, @1], YES, NO, NO);
    SGKaraokeLine *compound = wrapLine(@[@"甲", @"乙", @"丙", @"丁"],
        [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 3)]);
    wrapExtras(paired, compound, @[], @"a\u0301bcd");
    UIView *pairedView = wrapView(compound, edgeTwo, paired);
    NSArray<UIView *> *all = [pairedView valueForKey:@"words"];
    NSArray<UIView *> *spoken = all.count >= 4 ? [all subarrayWithRange:NSMakeRange(4, all.count - 4)] : @[];
    check([[[spoken valueForKey:@"word"] valueForKey:@"text"] isEqual:@[@"a\u0301b", @"cd"]],
          @"generated pronunciation splits a wrapped compound without splitting a combining grapheme");
    check([[[spoken valueForKey:@"word"] valueForKey:@"start"] isEqual:@[@0, @400]] &&
          [[[spoken valueForKey:@"word"] valueForKey:@"end"] isEqual:@[@400, @800]],
          @"pronunciation fragments retain the source words' clocks without invented sub-word timing");
    BOOL aligned = spoken.count == 2;
    if (aligned) {
        aligned = CGRectGetMinY(spoken[0].frame) > CGRectGetMinY(all[0].frame) &&
            CGRectGetMaxY(spoken[0].frame) < CGRectGetMinY(all[2].frame) &&
            CGRectGetMinY(spoken[1].frame) > CGRectGetMinY(all[2].frame);
        for (UIView *word in spoken)
            aligned &= CGRectGetMinX(word.frame) >= -0.01 && CGRectGetMaxX(word.frame) <= edgeTwo + 0.01;
    }
    check(aligned, @"each generated pronunciation fragment follows its source row within the row bounds");

    id above = ((id (*)(id, SEL, CGFloat, NSArray *, BOOL, BOOL, BOOL))objc_msgSend)([NSClassFromString(@"SGRKaraokeStyle") alloc],
        NSSelectorFromString(@"initWithSize:order:pronunciation:translation:romanised:"), 30, @[@1, @0], YES, NO, NO);
    wrapExtras(above, compound, @[], @"a\u0301bcd");
    CGFloat aboveWidth = 2 * wrapWide(@"甲", [above valueForKey:@"lyrics"]) + 1;
    UIView *aboveView = wrapView(compound, aboveWidth, above);
    NSArray<UIView *> *aboveWords = [aboveView valueForKey:@"words"];
    BOOL aboveAligned = aboveWords.count == 6;
    if (aboveAligned) {
        aboveAligned = CGRectGetMinY(aboveWords[4].frame) < CGRectGetMinY(aboveWords[0].frame) &&
            CGRectGetMinY(aboveWords[5].frame) > CGRectGetMaxY(aboveWords[0].frame) &&
            CGRectGetMinY(aboveWords[5].frame) < CGRectGetMinY(aboveWords[2].frame);
    }
    check(aboveAligned, @"pronunciation-first order places each fragment above its own source row");
}
