// Core Text draws into a bottom-left-origin bitmap. Credits are fitted in full, including the
// maker/uploader text Spicy Lyrics supplies; they are never governed by the Show source switch.
#import "LyricsPiPFrame.h"
#import "Shared/LyricsBackground/LyricsBackground.h"
#if SG_DRIVER
#import "Diagnostics/Diagnostics.h" // declares SGLyricsPiPFramePNG for the phone driver's pip.frame
#endif
#import <CoreText/CoreText.h>
#import <ImageIO/ImageIO.h>
#import <math.h>

static NSArray<NSString *> *sg_frame_content(NSArray<NSString *> *content) {
    NSMutableArray<NSString *> *three = [NSMutableArray arrayWithCapacity:7];
    for (NSUInteger i = 0; i < 7; i++) {
        id text = i < content.count ? content[i] : @"";
        [three addObject:[text isKindOfClass:NSString.class] ? text : @""];
    }
    return three;
}

static NSAttributedString *sg_attributed(NSString *text, CGFloat size, CTParagraphStyleRef paragraph, CGColorRef color,
    SGLyricsPiPStyle *style, NSUInteger role) {
    CTFontRef font = style ? SGLyricsPiPCreateFont(style, role, size) : CTFontCreateWithName(CFSTR("HelveticaNeue"), size, NULL);
    NSDictionary *attributes = @{(__bridge NSString *)kCTFontAttributeName: (__bridge id)font,
        (__bridge NSString *)kCTForegroundColorAttributeName: (__bridge id)color,
        (__bridge NSString *)kCTParagraphStyleAttributeName: (__bridge id)paragraph};
    NSAttributedString *string = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    CFRelease(font);
    return string;
}

static CTFramesetterRef sg_setter(NSString *text, CGFloat size, CTParagraphStyleRef paragraph, CGColorRef color,
    SGLyricsPiPStyle *style, NSUInteger role) {
    NSAttributedString *string = sg_attributed(text, size, paragraph, color, style, role);
    return CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)string);
}

static BOOL sg_fits(NSString *text, CGSize box, CGFloat size, CTParagraphStyleRef paragraph, CGColorRef color,
    SGLyricsPiPStyle *style, NSUInteger role) {
    CTFramesetterRef setter = sg_setter(text, size, paragraph, color, style, role);
    CGSize needed = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRangeMake(0, 0), NULL,
                                                                 CGSizeMake(box.width, CGFLOAT_MAX), NULL);
    CFRelease(setter);
    return needed.height <= box.height + 0.01;
}

// The one layout routine: FitText runs it without a context, DrawFrame with one, so the reported
// fit and the drawing can never disagree.
static SGLyricsPiPTextFit sg_layout(NSString *text, CGRect rect, CGFloat startSize, CGFloat minSize,
                                    CGFloat white, CGContextRef context, SGLyricsPiPStyle *style, NSUInteger role) {
    if (!text.length) return (SGLyricsPiPTextFit){startSize, 0, NO};

    CTTextAlignment alignment = !style || style.alignment == 1 ? kCTTextAlignmentCenter :
        style.alignment == 0 ? kCTTextAlignmentLeft : kCTTextAlignmentRight;
    CTParagraphStyleSetting setting = {kCTParagraphStyleSpecifierAlignment, sizeof(alignment), &alignment};
    CTParagraphStyleRef paragraph = CTParagraphStyleCreate(&setting, 1);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceGray();
    CGFloat components[] = {white, 1};
    CGColorRef color = CGColorCreate(space, components);
    CGColorSpaceRelease(space);

    // A handful of framesetters, not one per point: the largest whole-point size that fits height.
    NSInteger low = (NSInteger)ceil(minSize), high = (NSInteger)floor(startSize);
    NSInteger best = low - 1;
    while (low <= high) {
        NSInteger middle = low + (high - low) / 2;
        if (sg_fits(text, rect.size, (CGFloat)middle, paragraph, color, style, role)) {
            best = middle;
            low = middle + 1;
        } else {
            high = middle - 1;
        }
    }
    BOOL truncated = best < (NSInteger)ceil(minSize);
    CGFloat size = truncated ? minSize : (CGFloat)best;

    NSAttributedString *string = sg_attributed(text, size, paragraph, color, style, role);
    CTFramesetterRef setter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)string);
    CGPathRef path = CGPathCreateWithRect(rect, NULL);
    CTFrameRef frame = CTFramesetterCreateFrame(setter, CFRangeMake(0, 0), path, NULL);
    CFArrayRef lines = CTFrameGetLines(frame);
    CFIndex count = CFArrayGetCount(lines);
    CFRange visible = CTFrameGetVisibleStringRange(frame);
    truncated |= visible.location + visible.length < (CFIndex)text.length;

    if (context) {
        CGContextSaveGState(context);
        CGContextClipToRect(context, rect);
        CGContextSetTextMatrix(context, CGAffineTransformIdentity);
        // Core Text may leave the text position behind, and SaveGState does not save it.
        // A preceding ellipsized role must not offset the next role's entire CTFrame.
        CGContextSetTextPosition(context, 0, 0);
    }
    if (!truncated) {
        if (context && count) CTFrameDraw(frame, context);
    } else if (count) {
        CGPoint *origins = calloc((size_t)count, sizeof(CGPoint));
        CTFrameGetLineOrigins(frame, CFRangeMake(0, count), origins);
        if (context) {
            for (CFIndex i = 0; i < count - 1; i++) {
                CGContextSetTextPosition(context, rect.origin.x + origins[i].x, rect.origin.y + origins[i].y);
                CTLineDraw((CTLineRef)CFArrayGetValueAtIndex(lines, i), context);
            }
            // The last line that fits, its own text trimmed and "…" after it, cut again at the box width
            // when that overflows. Its own text, not the rest of the string: a hard break in what follows
            // would keep a rebuilt remainder narrow enough to dodge the cut, and the ellipsis with it.
            CFRange range = CTLineGetStringRange((CTLineRef)CFArrayGetValueAtIndex(lines, count - 1));
            NSString *tail = [[text substringWithRange:NSMakeRange((NSUInteger)range.location, (NSUInteger)range.length)]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            NSAttributedString *tailText = sg_attributed([tail stringByAppendingString:@"…"], size, paragraph, color, style, role);
            NSAttributedString *tokenText = sg_attributed(@"…", size, paragraph, color, style, role);
            CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)tailText);
            CTLineRef token = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)tokenText);
            CTLineRef cut = CTLineCreateTruncatedLine(line, rect.size.width, kCTLineTruncationEnd, token);
            CTLineRef drawn = cut ?: line;
            // A truncated line carries no paragraph alignment: centre it on the original baseline.
            double width = CTLineGetTypographicBounds(drawn, NULL, NULL, NULL);
            CGFloat flush = alignment == kCTTextAlignmentLeft ? 0 : alignment == kCTTextAlignmentRight ? 1 : .5;
            CGContextSetTextPosition(context, rect.origin.x + MAX(0, rect.size.width - width) * flush, rect.origin.y + origins[count - 1].y);
            CTLineDraw(drawn, context);
            if (cut) CFRelease(cut);
            CFRelease(line);
            CFRelease(token);
        }
        free(origins);
    }
    if (context) CGContextRestoreGState(context);

    CFRelease(frame);
    CGPathRelease(path);
    CFRelease(setter);
    CGColorRelease(color);
    CFRelease(paragraph);
    // A box too short for a single line at the minimum draws nothing, so nothing was cut with "…".
    return (SGLyricsPiPTextFit){size, (NSUInteger)count, truncated && count > 0};
}

SGLyricsPiPTextFit SGLyricsPiPFitText(NSString *text, CGSize box, CGFloat size, CGFloat minSize) {
    return sg_layout(text, CGRectMake(0, 0, box.width, box.height), size, minSize, 1, NULL, nil, 0);
}

void SGLyricsPiPDrawFrame(CGContextRef context, NSArray<NSString *> *content) {
    SGLyricsPiPStyle *style = SGLyricsPiPReadStyle();
    CGImageRef background = SGLyricsBackgroundCreate(NULL, style.raster,
        SGLyricsBackgroundRead(@"spotifyglass.lyrics.pip.background"));
    SGLyricsPiPDrawStyledFrame(context, content, style, background, NULL);
    if (background) CGImageRelease(background);
}

void SGLyricsPiPDrawFrameWithBackground(CGContextRef context, NSArray<NSString *> *content, CGImageRef background) {
    SGLyricsPiPDrawStyledFrame(context, content, SGLyricsPiPReadStyle(), background, NULL);
}

NSArray<NSValue *> *SGLyricsPiPFrameRects(NSArray<NSString *> *content, SGLyricsPiPStyle *style) {
    NSArray *texts = sg_frame_content(content);
    CGSize size = style.raster;
    CGFloat margin = 24, gap = 10, credit = 44;
    CGRect area = CGRectMake(margin, margin + credit + gap, size.width - margin * 2, size.height - margin * 2 - credit - gap);
    CGRect title = CGRectZero, artist = CGRectZero, cover = CGRectZero;
    if (style.info) {
        if (style.layout == 1) {
            cover = CGRectMake(margin, size.height - margin - 112, 112, 112);
            title = CGRectMake(margin, CGRectGetMinY(cover) - 76, 196, 64);
            artist = CGRectMake(margin, CGRectGetMinY(title) - 60, 196, 50);
            area.origin.x = 244;
            area.size.width = size.width - 244 - margin;
        } else {
            cover = CGRectMake(margin, size.height - margin - 80, 80, 80);
            title = CGRectMake(120, size.height - margin - 44, size.width - 144, 44);
            artist = CGRectMake(120, size.height - margin - 80, size.width - 144, 32);
            area.size.height -= 104;
        }
    }
    NSMutableArray *rects = [NSMutableArray array];
    for (NSUInteger i = 0; i < 8; i++) [rects addObject:[NSValue valueWithCGRect:CGRectZero]];
    rects[2] = [NSValue valueWithCGRect:CGRectMake(margin, margin, size.width - margin * 2, credit)];
    rects[5] = [NSValue valueWithCGRect:title]; rects[6] = [NSValue valueWithCGRect:artist];
    rects[7] = [NSValue valueWithCGRect:cover];
    NSArray *order = @[@0, @3, @4, @1];
    CGFloat total = 0; NSUInteger count = 0;
    CGFloat weights[] = {2.6, 1.4, 0, 1.6, 2};
    for (NSNumber *index in order) if ([texts[index.unsignedIntegerValue] length]) {
        total += weights[index.unsignedIntegerValue]; count++;
    }
    CGFloat available = area.size.height - gap * MAX(0, (NSInteger)count - 1), top = CGRectGetMaxY(area);
    for (NSNumber *index in order) {
        NSUInteger i = index.unsignedIntegerValue;
        if (![texts[i] length]) continue;
        CGFloat height = floor(available * weights[i] / total);
        rects[i] = [NSValue valueWithCGRect:CGRectMake(area.origin.x, top - height, area.size.width, height)];
        top -= height + gap;
    }
    return rects;
}
static NSUInteger roleFor(NSUInteger slot) { return slot == 0 ? 0 : slot == 3 ? 1 : slot == 4 ? 2 : 3; }
static CGFloat sizeFor(SGLyricsPiPStyle *s, NSUInteger slot) {
    return slot == 0 ? s.sizes[0].doubleValue : slot == 3 ? s.sizes[1].doubleValue :
        slot == 4 ? s.sizes[2].doubleValue : slot == 1 ? 26 : slot == 2 ? 17 : slot == 5 ? 26 : 20;
}
static CGFloat minFor(NSUInteger slot) { return slot == 0 ? 22 : slot == 2 ? 12 : 16; }
SGLyricsPiPTextFit SGLyricsPiPFitRole(NSString *text, CGSize box, SGLyricsPiPStyle *style, NSUInteger slot) {
    return sg_layout(text, (CGRect){CGPointZero, box}, sizeFor(style, slot), minFor(slot), 1, NULL, style, roleFor(slot));
}
void SGLyricsPiPDrawStyledFrame(CGContextRef context, NSArray<NSString *> *content,
    SGLyricsPiPStyle *style, CGImageRef background, CGImageRef cover) {
    if (!context) return;
    CGRect rect = (CGRect){CGPointZero, style.raster};
    if (background) CGContextDrawImage(context, rect, background);
    else { // allocation failure only; normal no-cover styling comes from the shared renderer
        CGContextSetRGBFillColor(context, 24 / 255.0, 24 / 255.0, 27 / 255.0, 1);
        CGContextFillRect(context, rect);
    }
    // A separate quiet reading surface keeps text legible even over a bright clear cover.
    CGContextSetRGBFillColor(context, 0, 0, 0, .30);
    CGContextFillRect(context, rect);
    NSArray *texts = sg_frame_content(content), *rects = SGLyricsPiPFrameRects(texts, style);
    CGRect artwork = [rects[7] CGRectValue];
    if (style.info) {
        CGContextSaveGState(context);
        CGPathRef rounded = CGPathCreateWithRoundedRect(artwork, 10, 10, NULL);
        CGContextAddPath(context, rounded); CGContextClip(context); CGPathRelease(rounded);
        CGContextSetRGBFillColor(context, .08, .08, .1, 1);
        CGContextFillRect(context, artwork);
        if (cover) {
            CGFloat scale = MAX(artwork.size.width / CGImageGetWidth(cover), artwork.size.height / CGImageGetHeight(cover));
            CGSize scaled = CGSizeMake(CGImageGetWidth(cover) * scale, CGImageGetHeight(cover) * scale);
            CGContextDrawImage(context, CGRectMake(CGRectGetMidX(artwork) - scaled.width / 2,
                CGRectGetMidY(artwork) - scaled.height / 2, scaled.width, scaled.height), cover);
        }
        CGContextRestoreGState(context);
    }
    for (NSUInteger i = 0; i < 7; i++) {
        CGRect box = [rects[i] CGRectValue];
        if (CGRectIsEmpty(box)) continue;
        CGFloat white = i == 0 || i == 5 ? 1 : i == 1 ? .58 : i == 3 ? .82 : .72;
        sg_layout(texts[i], box, sizeFor(style, i), minFor(i), white, context, style, roleFor(i));
    }
}

NSData *SGLyricsPiPFramePNG(NSArray<NSString *> *content) {
    return SGLyricsPiPStyledPNG(content, SGLyricsPiPReadStyle(), NULL);
}
NSData *SGLyricsPiPStyledPNG(NSArray<NSString *> *content, SGLyricsPiPStyle *style, CGImageRef cover) {
    size_t width = style.raster.width, height = style.raster.height;
    NSMutableData *pixels = [NSMutableData dataWithLength:width * 4 * height];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, width, height, 8, width * 4, space,
                                                 kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(space);
    if (!context) return nil;
    CGImageRef background = SGLyricsBackgroundCreate(cover, style.raster,
        SGLyricsBackgroundRead(@"spotifyglass.lyrics.pip.background"));
    SGLyricsPiPDrawStyledFrame(context, content, style, background, cover);
    if (background) CGImageRelease(background);
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (!image) return nil;
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, CFSTR("public.png"), 1, NULL);
    if (!destination) { CGImageRelease(image); return nil; }
    CGImageDestinationAddImage(destination, image, NULL);
    BOOL ok = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    CGImageRelease(image);
    return ok ? data : nil;
}
