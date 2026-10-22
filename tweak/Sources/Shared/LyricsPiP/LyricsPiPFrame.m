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

const size_t SGLyricsPiPFrameWidth = 640, SGLyricsPiPFrameHeight = 360;

typedef struct {
    CGRect rect;
    CGFloat size, minSize, white;
} SGFrameBox;

static const SGFrameBox kBoxes[] = {
    {{{24, 156}, {592, 180}}, 40, 24, 1},
    {{{24, 76}, {592, 76}}, 26, 16, 0.65},
    {{{24, 10}, {592, 58}}, 17, 12, 0.7},
};

static NSArray<NSString *> *sg_frame_content(NSArray<NSString *> *content) {
    NSMutableArray<NSString *> *three = [NSMutableArray arrayWithCapacity:3];
    for (NSUInteger i = 0; i < 3; i++) {
        id text = i < content.count ? content[i] : @"";
        [three addObject:[text isKindOfClass:NSString.class] ? text : @""];
    }
    return three;
}

static NSAttributedString *sg_attributed(NSString *text, CGFloat size, CTParagraphStyleRef paragraph, CGColorRef color) {
    CTFontRef font = CTFontCreateWithName(CFSTR("HelveticaNeue"), size, NULL);
    NSDictionary *attributes = @{(__bridge NSString *)kCTFontAttributeName: (__bridge id)font,
        (__bridge NSString *)kCTForegroundColorAttributeName: (__bridge id)color,
        (__bridge NSString *)kCTParagraphStyleAttributeName: (__bridge id)paragraph};
    NSAttributedString *string = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    CFRelease(font);
    return string;
}

static CTFramesetterRef sg_setter(NSString *text, CGFloat size, CTParagraphStyleRef paragraph, CGColorRef color) {
    NSAttributedString *string = sg_attributed(text, size, paragraph, color);
    return CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)string);
}

static BOOL sg_fits(NSString *text, CGSize box, CGFloat size, CTParagraphStyleRef paragraph, CGColorRef color) {
    CTFramesetterRef setter = sg_setter(text, size, paragraph, color);
    CGSize needed = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRangeMake(0, 0), NULL,
                                                                 CGSizeMake(box.width, CGFLOAT_MAX), NULL);
    CFRelease(setter);
    return needed.height <= box.height + 0.01;
}

// The one layout routine: FitText runs it without a context, DrawFrame with one, so the reported
// fit and the drawing can never disagree.
static SGLyricsPiPTextFit sg_layout(NSString *text, CGRect rect, CGFloat startSize, CGFloat minSize,
                                    CGFloat white, CGContextRef context) {
    if (!text.length) return (SGLyricsPiPTextFit){startSize, 0, NO};

    CTTextAlignment alignment = kCTTextAlignmentCenter;
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
        if (sg_fits(text, rect.size, (CGFloat)middle, paragraph, color)) {
            best = middle;
            low = middle + 1;
        } else {
            high = middle - 1;
        }
    }
    BOOL truncated = best < (NSInteger)ceil(minSize);
    CGFloat size = truncated ? minSize : (CGFloat)best;

    NSAttributedString *string = sg_attributed(text, size, paragraph, color);
    CTFramesetterRef setter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)string);
    CGPathRef path = CGPathCreateWithRect(rect, NULL);
    CTFrameRef frame = CTFramesetterCreateFrame(setter, CFRangeMake(0, 0), path, NULL);
    CFArrayRef lines = CTFrameGetLines(frame);
    CFIndex count = CFArrayGetCount(lines);

    if (context) CGContextSetTextMatrix(context, CGAffineTransformIdentity);
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
            NSAttributedString *tailText = sg_attributed([tail stringByAppendingString:@"…"], size, paragraph, color);
            NSAttributedString *tokenText = sg_attributed(@"…", size, paragraph, color);
            CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)tailText);
            CTLineRef token = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)tokenText);
            CTLineRef cut = CTLineCreateTruncatedLine(line, rect.size.width, kCTLineTruncationEnd, token);
            CTLineRef drawn = cut ?: line;
            // A truncated line carries no paragraph alignment: centre it on the original baseline.
            double width = CTLineGetTypographicBounds(drawn, NULL, NULL, NULL);
            CGContextSetTextPosition(context, rect.origin.x + (rect.size.width - width) / 2, rect.origin.y + origins[count - 1].y);
            CTLineDraw(drawn, context);
            if (cut) CFRelease(cut);
            CFRelease(line);
            CFRelease(token);
        }
        free(origins);
    }

    CFRelease(frame);
    CGPathRelease(path);
    CFRelease(setter);
    CGColorRelease(color);
    CFRelease(paragraph);
    // A box too short for a single line at the minimum draws nothing, so nothing was cut with "…".
    return (SGLyricsPiPTextFit){size, (NSUInteger)count, truncated && count > 0};
}

SGLyricsPiPTextFit SGLyricsPiPFitText(NSString *text, CGSize box, CGFloat size, CGFloat minSize) {
    return sg_layout(text, CGRectMake(0, 0, box.width, box.height), size, minSize, 1, NULL);
}

void SGLyricsPiPDrawFrame(CGContextRef context, NSArray<NSString *> *content) {
    CGImageRef background = SGLyricsBackgroundCreate(NULL, CGSizeMake(SGLyricsPiPFrameWidth, SGLyricsPiPFrameHeight),
        SGLyricsBackgroundRead(@"spotifyglass.lyrics.pip.background"));
    SGLyricsPiPDrawFrameWithBackground(context, content, background);
    if (background) CGImageRelease(background);
}

void SGLyricsPiPDrawFrameWithBackground(CGContextRef context, NSArray<NSString *> *content, CGImageRef background) {
    if (!context) return;
    CGRect rect = CGRectMake(0, 0, SGLyricsPiPFrameWidth, SGLyricsPiPFrameHeight);
    if (background) CGContextDrawImage(context, rect, background);
    else { // allocation failure only; normal no-cover styling comes from the shared renderer
        CGContextSetRGBFillColor(context, 24 / 255.0, 24 / 255.0, 27 / 255.0, 1);
        CGContextFillRect(context, rect);
    }
    NSArray<NSString *> *three = sg_frame_content(content);
    for (NSUInteger i = 0; i < 3; i++) {
        sg_layout(three[i], kBoxes[i].rect, kBoxes[i].size, kBoxes[i].minSize, kBoxes[i].white, context);
    }
}

NSData *SGLyricsPiPFramePNG(NSArray<NSString *> *content) {
    size_t width = SGLyricsPiPFrameWidth, height = SGLyricsPiPFrameHeight;
    NSMutableData *pixels = [NSMutableData dataWithLength:width * 4 * height];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, width, height, 8, width * 4, space,
                                                 kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(space);
    if (!context) return nil;
    SGLyricsPiPDrawFrame(context, content);
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
