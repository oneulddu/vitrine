#import "Core/SGCore.h"
#import "AIServicesInternal.h"

static const NSUInteger kMaxProseTexts = 2000, kMaxProseTextUTF16Units = 64000;
static const NSUInteger kMaxProseInputUTF16Units = 128000, kMaxProseOutputUTF16Units = 256000;

NSString *SGLyricsProseTooLong(void) {
    return SGL(@"settings.translation.text.error.toolong", @"This explanation is too long to translate with this service.");
}

BOOL SGLyricsProseTextsValid(NSArray<NSString *> *texts) {
    if (![texts isKindOfClass:NSArray.class] || !texts.count || texts.count > kMaxProseTexts) return NO;
    NSUInteger size = 0;
    for (id text in texts) {
        if (![text isKindOfClass:NSString.class] || [text length] > kMaxProseTextUTF16Units ||
            [text length] > kMaxProseInputUTF16Units - size) return NO;
        size += [text length];
    }
    return YES;
}

BOOL SGLyricsProseReplyValid(NSArray<NSString *> *answer, NSArray<NSString *> *texts) {
    if (![answer isKindOfClass:NSArray.class] || answer.count != texts.count) return NO;
    NSUInteger size = 0;
    for (NSUInteger i = 0; i < texts.count; i++) {
        id translated = answer[i];
        if (![translated isKindOfClass:NSString.class] || [translated length] > kMaxProseOutputUTF16Units - size) return NO;
        size += [translated length];
        if ([texts[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length &&
            ![translated stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) return NO;
    }
    return YES;
}

// Plan entries are segment indices or literal separators. Trimming only the edges keeps every source
// paragraph separator (including CRLF and empty paragraphs) outside the translator's control.
static BOOL segmentFits(NSString *text, NSUInteger limit, SGProseSegmentUnit unit) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (unit == SGProseSegmentUTF16) return trimmed.length <= limit;
    return [NSJSONSerialization dataWithJSONObject:@[trimmed] options:0 error:nil].length <= limit;
}

static BOOL appendPiece(NSString *piece, NSUInteger limit, SGProseSegmentUnit unit, NSMutableArray *segments, NSMutableArray *plan) {
    NSCharacterSet *words = NSCharacterSet.whitespaceAndNewlineCharacterSet.invertedSet;
    NSRange first = [piece rangeOfCharacterFromSet:words];
    if (first.location == NSNotFound) { [plan addObject:piece]; return YES; }
    NSRange last = [piece rangeOfCharacterFromSet:words options:NSBackwardsSearch];
    if (first.location) [plan addObject:[piece substringToIndex:first.location]];
    NSUInteger cursor = first.location, end = NSMaxRange(last);
    // Paid AI jobs never split a single over-budget sentence into fragments.
    if (unit == SGProseSegmentJSONBytes && !segmentFits(piece, limit, unit)) return NO;
    while (cursor < end) {
        NSUInteger length = unit == SGProseSegmentJSONBytes ? end - cursor : MIN(limit, end - cursor);
        // An unusually long sentence/token still has to fit; never cut a surrogate pair or grapheme.
        NSRange boundary = [piece rangeOfComposedCharacterSequenceAtIndex:cursor + length - 1];
        if (NSMaxRange(boundary) > cursor + length) length = boundary.location - cursor;
        if (!length || segments.count >= kMaxProseTexts) return NO;
        [plan addObject:@(segments.count)];
        [segments addObject:[piece substringWithRange:NSMakeRange(cursor, length)]];
        cursor += length;
    }
    if (end < piece.length) [plan addObject:[piece substringFromIndex:end]];
    return YES;
}

void SGLyricsTranslateSegments(NSArray<NSString *> *texts, NSUInteger maxSize, SGProseSegmentUnit unit,
    void (^send)(NSArray<NSString *> *, void (^)(NSArray<NSString *> *, NSString *)),
    void (^done)(NSArray<NSString *> *, NSString *)) {
    if (!SGLyricsProseTextsValid(texts)) { done(nil, SGLyricsProseTooLong()); return; }
    NSMutableArray *segments = [NSMutableArray array], *plans = [NSMutableArray array];
    for (NSString *text in texts) {
        NSMutableArray *plan = [NSMutableArray array];
        NSUInteger cursor = 0;
        while (cursor < text.length) {
            NSUInteger end, contentsEnd;
            [text getParagraphStart:NULL end:&end contentsEnd:&contentsEnd forRange:NSMakeRange(cursor, 0)];
            NSString *paragraph = [text substringWithRange:NSMakeRange(cursor, contentsEnd - cursor)];
            __block BOOL valid = YES;
            if (segmentFits(paragraph, maxSize, unit) ||
                ![paragraph stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length)
                valid = appendPiece(paragraph, maxSize, unit, segments, plan);
            else {
                __block NSRange group = NSMakeRange(0, 0);
                [paragraph enumerateSubstringsInRange:NSMakeRange(0, paragraph.length) options:NSStringEnumerationBySentences
                    usingBlock:^(NSString *sentence, NSRange range, NSRange enclosing, BOOL *stop) {
                        // Keep the web path's existing sentence batches; pack AI sentences up to its byte
                        // budget so ordinary prose does not pay for a separate call per short sentence.
                        if (unit == SGProseSegmentUTF16) {
                            valid = appendPiece([paragraph substringWithRange:enclosing], maxSize, unit, segments, plan);
                        } else {
                            NSRange combined = NSMakeRange(group.location, NSMaxRange(enclosing) - group.location);
                            if (group.length && !segmentFits([paragraph substringWithRange:combined], maxSize, unit)) {
                                valid = appendPiece([paragraph substringWithRange:group], maxSize, unit, segments, plan);
                                group = enclosing;
                            } else group = combined;
                        }
                        *stop = !valid;
                    }];
                if (valid && group.length)
                    valid = appendPiece([paragraph substringWithRange:group], maxSize, unit, segments, plan);
            }
            if (!valid) { done(nil, SGLyricsProseTooLong()); return; }
            [plan addObject:[text substringWithRange:NSMakeRange(contentsEnd, end - contentsEnd)]];
            cursor = end;
        }
        [plans addObject:plan];
    }
    if (!segments.count) { done(texts, nil); return; }
    send(segments, ^(NSArray<NSString *> *answer, NSString *error) {
        if (error || !SGLyricsProseReplyValid(answer, segments)) {
            done(nil, error ?: SGL(@"settings.translation.text.error.unreadable", @"The translation's answer could not be read. Try again."));
            return;
        }
        NSMutableArray *out = [NSMutableArray array];
        for (NSArray *plan in plans) {
            NSMutableString *text = [NSMutableString string];
            for (id part in plan) [text appendString:[part isKindOfClass:NSNumber.class] ? answer[[part unsignedIntegerValue]] : part];
            [out addObject:text];
        }
        done(out, nil);
    });
}
