// SGLyricsClip.h says what this draws. The words are laid out once per clip and only the backdrop moves,
// so an animated clip costs a scaled image draw and an encode a frame.
#import <Accelerate/Accelerate.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreText/CoreText.h>
#import "SGLyricsClip.h"
#import "Shared/LyricsBackground/LyricsBackground.h"

// The lock screen fills a 9:19.5 screen with the 3:4 clip, scaled to its height, so only the middle kScreen of
// the clip's width shows and heights map one to one. The words are left-aligned kMargin of that shown width in
// from its left edge and wrap at kColumn of it; the middle of the words sits kCentreY down, in the upper middle,
// their top no higher than kTop, clear of the clock above and the media controls (the bottom 35%) below.
// ponytail: from the screen's shape and a reference picture, not measured on a lock screen; tune on a device.
static const CGFloat kScreen = 9 / 19.5 * 4 / 3;
static const CGFloat kMargin = 0.08, kColumn = 0.84;
static const CGFloat kCentreY = 0.4, kTop = 0.17;
// The words' size as a share of the width, made smaller down to kSmallest of it while they run taller
// than kTallest of the height.
static const CGFloat kFont = 0.047;
static const CGFloat kSmallest = 0.6;
static const CGFloat kTallest = 0.4;
// The lines either side of the line (the next, and over moving artwork the one sung last) in the regular weight
// at this share of its size, kNextAlpha white, kNextGap of the line's size from it.
static const CGFloat kNextScale = 0.6, kNextAlpha = 0.5, kNextGap = 0.5;
// A translation sits close under its line, in the regular weight at this share of the line's size and this white.
static const CGFloat kTranslationScale = 0.62, kTranslationAlpha = 0.8, kTranslationGap = 0.15;
// A still is one frame held this long; an animated clip breathes once over kLoopSeconds, which is all it
// plays before the lock screen loops it.
static const int32_t kStillSeconds = 2;
static const int32_t kLoopSeconds = 4;
static const int32_t kFPS = 15;   // the breath is slow; at 24 a line took about 4 s to write on the CPU
static const CGFloat kBreath = 0.06;   // how much bigger the cover grows at the top of a breath
// Over moving artwork, judged on bright, busy and dark clips in harness/lyrics-clip: the picture is dimmed by
// kMotionDim, and by kBandDim where the words sit, fading between the two over kBandReach of the height above
// and below the middle, so white in it stays under 0.4 of the words' white there; behind the words it is
// blurred, a tent kSoftWidth of the width across (127 pixels at most), so no pattern in it crosses the letters,
// the dimmed ones included; the words carry a tight dark shadow kShadowBlur of the font size wide, and the dimmed lines are
// kMotionNextAlpha white. Over a bright picture the band is darker, by its first frame, held for the clip:
// enough that the brightest tenth behind the words comes to kBandLight of white, up to kBandDarkest.
static const CGFloat kMotionDim = 0.25, kBandDim = 0.6, kBandReach = 0.3, kSoftWidth = 0.16;
static const CGFloat kBandLight = 0.22, kBandDarkest = 0.8;
static const CGFloat kShadowAlpha = 0.9, kShadowBlur = 0.15, kMotionNextAlpha = 0.55;
// A faster video keeps only this many frames a second: each costs a draw on the CPU.
static const double kMotionFPS = 30;

CGSize SGLyricsClipSize(CGFloat pixels) {
    CGFloat width = MAX(floor(pixels / 16) * 16, 16);
    return CGSizeMake(width, round(width * 4 / 3 / 16) * 16);
}

static CGContextRef newContext(CGSize size, void *data, size_t bytesPerRow) {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(data, (size_t)size.width, (size_t)size.height, 8, bytesPerRow, space,
                                                 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    return context;
}

CGImageRef SGLyricsClipBackdrop(CGImageRef cover, CGSize size) {
    return SGLyricsBackgroundCreate(cover, size, SGLyricsBackgroundDefault(SGLyricsBackgroundLockScreen));
}

static BOOL isHangul(unichar c) {
    return (c >= 0xAC00 && c <= 0xD7A3) || (c >= 0x1100 && c <= 0x11FF) || (c >= 0x3130 && c <= 0x318F);
}

// Core Text breaks Korean inside a word, whatever language the text is tagged with; Korean breaks between words. A
// word joiner between two Hangul letters keeps each word whole, so its lines break at the spaces. A word wider than
// the column is still broken, as Core Text breaks any word that does not fit.
static NSString *keptWhole(NSString *text) {
    if (![text containsString:@" "]) return text;
    NSMutableString *kept = [NSMutableString stringWithCapacity:text.length + text.length / 2];
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (i && isHangul(c) && isHangul([text characterAtIndex:i - 1])) [kept appendString:@"\u2060"];
        [kept appendFormat:@"%C", c];
    }
    return kept;
}

// The line sung last (dimmed, smaller), the line, its translation, and the next line (dimmed, smaller), each its
// own paragraph. The translation goes only with the line it belongs to.
static NSAttributedString *wordsAt(NSString *previous, NSString *line, NSString *translation, NSString *next,
                                   CGFloat fontSize, CGFloat dimAlpha) {
    if (!line.length) translation = nil;
    CTFontRef font = CTFontCreateUIFontForLanguage(kCTFontUIFontEmphasizedSystem, fontSize, NULL);
    CTFontRef small = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, fontSize * kTranslationScale, NULL);
    CTFontRef aside = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, fontSize * kNextScale, NULL);
    CGFloat spacing = fontSize * kNextGap, gap = fontSize * kTranslationGap, tall = round(fontSize * kTranslationScale * 1.3);
    CTParagraphStyleSetting settings[] = {
        {kCTParagraphStyleSpecifierParagraphSpacingBefore, sizeof(spacing), &spacing},
    };
    // A fallback font for its script (Korean's, Japanese's) sets the lines further apart than the line's own: held
    // to the line's spacing.
    CTParagraphStyleSetting under[] = {
        {kCTParagraphStyleSpecifierParagraphSpacingBefore, sizeof(gap), &gap},
        {kCTParagraphStyleSpecifierMaximumLineHeight, sizeof(tall), &tall},
        {kCTParagraphStyleSpecifierMinimumLineHeight, sizeof(tall), &tall},
    };
    CTParagraphStyleRef paragraph = CTParagraphStyleCreate(settings, 1), close = CTParagraphStyleCreate(under, 3);
    translation = keptWhole(translation);
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGFloat white[] = {1, 1, 1, 1}, dim[] = {1, 1, 1, dimAlpha}, soft[] = {1, 1, 1, kTranslationAlpha};
    CGColorRef lit = CGColorCreate(space, white), unlit = CGColorCreate(space, dim), told = CGColorCreate(space, soft);
    NSMutableAttributedString *words = [NSMutableAttributedString new];
    NSString *texts[] = {previous, line, translation, next};
    for (int i = 0; i < 4; i++) {
        if (!texts[i].length) continue;
        BOOL isTranslation = i == 2;
        NSMutableDictionary *attributes = [@{
            (id)kCTFontAttributeName: (__bridge id)(i == 1 ? font : isTranslation ? small : aside),
            (id)kCTParagraphStyleAttributeName: (__bridge id)(isTranslation ? close : paragraph),
            (id)kCTForegroundColorAttributeName: (__bridge id)(i == 1 ? lit : isTranslation ? told : unlit),
        } mutableCopy];
        NSString *text = words.length ? [@"\n" stringByAppendingString:texts[i]] : texts[i];
        [words appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:attributes]];
    }
    CFRelease(font);
    CFRelease(small);
    CFRelease(aside);
    CFRelease(paragraph);
    CFRelease(close);
    CGColorRelease(lit);
    CGColorRelease(unlit);
    CGColorRelease(told);
    CGColorSpaceRelease(space);
    return words;
}

// The words alone on a clear image the size of the clip, nil when there are none. Over moving artwork they
// carry a shadow, the dimmed lines are less dim, and the image is only the words' box, which `drawn` gets
// the place of in the clip.
static CGImageRef newWords(NSString *previous, NSString *line, NSString *translation, NSString *next, CGSize size,
                           CGRect *drawn) CF_RETURNS_RETAINED {
    if (!previous.length && !line.length && !next.length) return NULL;
    CGFloat screen = size.width * kScreen, width = round(screen * kColumn);
    CGFloat fontSize = size.width * kFont;
    CTFramesetterRef setter = NULL;
    CGSize fits = CGSizeZero;
    // A long line is set smaller until the two lines fit; past the smallest size it runs taller.
    for (CGFloat scale = 1; scale >= kSmallest - 0.01; scale -= 0.1) {
        if (setter) CFRelease(setter);
        setter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)wordsAt(previous, line, translation, next,
            fontSize * scale, drawn ? kMotionNextAlpha : kNextAlpha));
        fits = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRangeMake(0, 0), NULL, CGSizeMake(width, CGFLOAT_MAX), NULL);
        if (fits.height <= size.height * kTallest) break;
    }
    CGFloat height = ceil(fits.height) + 1;
    CGFloat top = MAX(size.height * kCentreY - height / 2, size.height * kTop);
    // Core Graphics counts up from the bottom.
    CGRect box = CGRectMake(round((size.width - screen) / 2 + screen * kMargin), round(size.height - top - height), width, height);
    CGPathRef path = CGPathCreateWithRect(box, NULL);
    CTFrameRef frame = CTFramesetterCreateFrame(setter, CFRangeMake(0, 0), path, NULL);
    CGContextRef context = newContext(size, NULL, 0);
    if (drawn) {
        CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGFloat shade[] = {0, 0, 0, kShadowAlpha};
        CGColorRef color = CGColorCreate(space, shade);
        CGContextSetShadowWithColor(context, CGSizeZero, fontSize * kShadowBlur, color);
        CGColorRelease(color);
        CGColorSpaceRelease(space);
    }
    CTFrameDraw(frame, context);
    CGImageRef words = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (drawn) {
        // Out to the shadow's reach, inside the clip; an image is cut from the top, Core Graphics counts from the bottom.
        *drawn = CGRectIntersection(CGRectIntegral(CGRectInset(box, -fontSize, -fontSize)), (CGRect){CGPointZero, size});
        CGImageRef cut = CGImageCreateWithImageInRect(words, CGRectMake(drawn->origin.x, size.height - CGRectGetMaxY(*drawn),
                                                                        drawn->size.width, drawn->size.height));
        CGImageRelease(words);
        words = cut;
    }
    CFRelease(frame);
    CGPathRelease(path);
    CFRelease(setter);
    return words;
}

// A frame `phase` of the way through the loop, 0 to 1, into `context`.
static void drawFrame(CGContextRef context, CGImageRef backdrop, CGImageRef words, CGSize size, double phase) {
    CGFloat grow = kBreath * (1 - cos(2 * M_PI * phase)) / 2;
    CGRect bounds = {CGPointZero, size};
    CGContextDrawImage(context, CGRectInset(bounds, -size.width * grow / 2, -size.height * grow / 2), backdrop);
    if (words) CGContextDrawImage(context, bounds, words);
}

CGImageRef SGLyricsClipFrame(CGImageRef backdrop, NSString *line, NSString *translation, NSString *next, CGSize size) {
    CGImageRef words = newWords(nil, line, translation, next, size, NULL);
    CGContextRef context = newContext(size, NULL, 0);
    drawFrame(context, backdrop, words, size, 0);
    CGImageRef frame = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    CGImageRelease(words);
    return frame;
}

BOOL SGLyricsClipWrite(NSURL *file, CGImageRef backdrop, NSString *line, NSString *translation, NSString *next, CGSize size,
                       SGLyricsClipStyle style) {
    // Written beside the file and moved over it once whole, so a clip cut off halfway is never found.
    NSURL *partial = [file URLByAppendingPathExtension:@"partial"];
    [NSFileManager.defaultManager removeItemAtURL:partial error:nil];
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:partial fileType:AVFileTypeMPEG4 error:nil];
    if (!writer) return NO;
    int32_t frames = style == SGLyricsClipAnimated ? kLoopSeconds * kFPS : 1;
    CMTime length = CMTimeMake(style == SGLyricsClipAnimated ? kLoopSeconds : kStillSeconds, 1);
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @(size.width),
        AVVideoHeightKey: @(size.height),
        // The CPU backdrop is sRGB. Explicit input/output color tagging prevents the encoder from
        // treating its samples as already Rec.709, which brightened decoded covers versus previews.
        AVVideoColorPropertiesKey: @{
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        },
        AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: @(2000000), AVVideoMaxKeyFrameIntervalKey: @(kFPS)},
    }];
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
        sourcePixelBufferAttributes:@{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (id)kCVPixelBufferWidthKey: @(size.width),
            (id)kCVPixelBufferHeightKey: @(size.height),
        }];
    if (![writer canAddInput:input]) return NO;
    [writer addInput:input];
    if (![writer startWriting]) return NO;
    [writer startSessionAtSourceTime:kCMTimeZero];
    CGImageRef words = newWords(nil, line, translation, next, size, NULL);
    BOOL ok = YES;
    for (int32_t i = 0; i < frames && ok; i++) {
        while (!input.readyForMoreMediaData && writer.status == AVAssetWriterStatusWriting) [NSThread sleepForTimeInterval:0.002];
        CVPixelBufferRef buffer = NULL;
        ok = writer.status == AVAssetWriterStatusWriting && adaptor.pixelBufferPool
            && CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &buffer) == kCVReturnSuccess;
        if (!ok) break;
        CVPixelBufferLockBaseAddress(buffer, 0);
        CGContextRef context = newContext(size, CVPixelBufferGetBaseAddress(buffer), CVPixelBufferGetBytesPerRow(buffer));
        drawFrame(context, backdrop, words, size, (double)i / frames);
        CGContextRelease(context);
        CVPixelBufferUnlockBaseAddress(buffer, 0);
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_sRGB, kCVAttachmentMode_ShouldPropagate);
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
        ok = [adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(i, kFPS)];
        CVPixelBufferRelease(buffer);
    }
    CGImageRelease(words);
    if (!ok) {
        [writer cancelWriting];
        return NO;
    }
    [input markAsFinished];
    // The last frame, or a still's only one, is held to the end of the loop.
    [writer endSessionAtSourceTime:length];
    dispatch_semaphore_t written = dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(written); }];
    dispatch_semaphore_wait(written, DISPATCH_TIME_FOREVER);
    if (writer.status != AVAssetWriterStatusCompleted) return NO;
    [NSFileManager.defaultManager removeItemAtURL:file error:nil];
    return [NSFileManager.defaultManager moveItemAtURL:partial toURL:file error:nil];
}

// Over moving artwork. The video is read as BGRA, the dimming and the words are drawn into each frame where
// it lies, at the video's own size, and the encoder cuts the 3:4 middle out as SGMotionClip.m's cut does,
// so the picture is never scaled on the CPU: a frame costs a fill, a gradient and one image draw.

typedef struct {
    CGSize stored, cut;   // the video's size, and the 3:4 middle of it the clip keeps
    double length;        // the video's, in seconds
} Motion;

// The video's track, nil when it has none or a transform turns it.
static AVAssetTrack *motionTrack(AVURLAsset *asset, Motion *motion) {
    __block AVAssetTrack *track = nil;
    dispatch_semaphore_t loaded = dispatch_semaphore_create(0);
    [asset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> *tracks, NSError *error) {
        track = tracks.firstObject;
        dispatch_semaphore_signal(loaded);
    }];
    dispatch_semaphore_wait(loaded, DISPATCH_TIME_FOREVER);
    // shortcut: a turned video (none seen among Canvases or Apple Music's covers) falls back to the blurred
    // cover; drawing the words turned with it is the step up if one turns up.
    if (!track || !CGAffineTransformIsIdentity(track.preferredTransform)) return nil;
    // Whole pixels: the decoded frames are, and drawOver checks each against this.
    CGSize stored = CGSizeMake(round(track.naturalSize.width), round(track.naturalSize.height));
    double length = CMTimeGetSeconds(track.timeRange.duration);
    if (stored.width < 16 || stored.height < 16 || !(length > 0)) return nil;
    CGSize cut = stored.width / stored.height > 0.75 ? CGSizeMake(stored.height * 0.75, stored.height)
                                                     : CGSizeMake(stored.width, stored.width / 0.75);
    // H.264 takes even sides, rounded down so the cut stays inside the picture.
    *motion = (Motion){stored, CGSizeMake(floor(cut.width / 2) * 2, floor(cut.height / 2) * 2), length};
    return track;
}

// The cut's place in the stored frame, which Core Graphics counts from the bottom; it is the middle, so the
// same from the top.
static CGRect cutIn(Motion motion) {
    return CGRectMake(round((motion.stored.width - motion.cut.width) / 2), round((motion.stored.height - motion.cut.height) / 2),
                      motion.cut.width, motion.cut.height);
}

// What is drawn over every frame of a clip, made once for it.
typedef struct {
    CGImageRef words;     // the words' box, NULL for none
    CGRect drawn;         // where it goes in the cut
    uint16_t *keep;       // how much of the picture each row of the cut keeps, of 256, from the top: the dimming
    CGRect soft;          // the rows behind the words, across the cut, in the stored frame
    uint8_t *blurred;     // those rows blurred, NULL with no words
    uint16_t *feather;    // how much of the blurred rows each row takes, of 256, fading in and out at the top and bottom
    BOOL fitted;          // whether `keep` is set to the picture behind the words yet, which the first frame does
} Over;

// How dark row `y` of `height` (from the top) is made: `band` across the middle 40% of the band about the
// words, kMotionDim past it, straight between.
static CGFloat dimAt(size_t y, size_t height, CGFloat band) {
    CGFloat reach = height * kBandReach, t = (y - (height * kCentreY - reach)) / (2 * reach);
    if (t <= 0 || t >= 1) return kMotionDim;
    CGFloat edge = MIN(MIN(t, 1 - t) / 0.3, 1);
    return kMotionDim + (band - kMotionDim) * edge;
}

static void setKeep(Over *over, size_t rows, CGFloat band) {
    for (size_t y = 0; y < rows; y++) over->keep[y] = (uint16_t)round(256 * (1 - dimAt(y, rows, band)));
}

static Over makeOver(Motion motion, NSString *previous, NSString *line, NSString *translation, NSString *next) {
    Over over = {0};
    over.words = newWords(previous, line, translation, next, motion.cut, &over.drawn);
    size_t rows = (size_t)motion.cut.height;
    over.keep = malloc(rows * sizeof(uint16_t));
    setKeep(&over, rows, kBandDim);
    if (!over.words) return over;
    CGRect cut = cutIn(motion);
    // A font size past the margin newWords leaves about the words, itself a font size, and faded in over both, so
    // every line is on picture blurred whole and the blur's edge is gentle and away from them.
    CGFloat reach = round(motion.cut.width * kFont);
    over.soft = CGRectIntersection(CGRectMake(cut.origin.x, cut.origin.y + over.drawn.origin.y - reach, cut.size.width,
                                              over.drawn.size.height + 2 * reach), cut);
    size_t width = (size_t)over.soft.size.width, height = (size_t)over.soft.size.height;
    size_t fade = MAX(MIN((size_t)(2 * reach), height / 2), 1);
    over.blurred = malloc(width * height * 4);
    over.feather = malloc(height * sizeof(uint16_t));
    for (size_t y = 0; y < height; y++) over.feather[y] = (uint16_t)(256 * MIN(1.0, MIN(y, height - 1 - y) / (double)fade));
    return over;
}

static void freeOver(Over over) {
    CGImageRelease(over.words);
    free(over.keep);
    free(over.blurred);
    free(over.feather);
}

// The softening, the dimming and the words, drawn into `buffer`, a BGRA frame of the video: the rows behind
// the words blurred (Accelerate's tent blur) and faded in, on the first frame the band's darkness set by how
// bright they are, every row of the cut darkened by its share in one pass, and one image the size of the
// words. All on the CPU. NO, with the frame left as it is, for a frame of another size or format than the
// track states, so the clip is not written without its words.
static BOOL drawOver(CVPixelBufferRef buffer, Motion motion, Over *over) {
    CVPixelBufferLockBaseAddress(buffer, 0);
    uint8_t *base = CVPixelBufferGetBaseAddress(buffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(buffer);
    CGRect cut = cutIn(motion);
    // Every write below is placed by the track's natural size, which the file states: a decoded frame of another
    // size or format is left as it is rather than written past its end.
    size_t frameWidth = CVPixelBufferGetWidth(buffer), frameHeight = CVPixelBufferGetHeight(buffer);
    CGRect frame = CGRectMake(0, 0, frameWidth, frameHeight);
    if (!base || CVPixelBufferIsPlanar(buffer) || CVPixelBufferGetPixelFormatType(buffer) != kCVPixelFormatType_32BGRA
        || frameWidth != (size_t)motion.stored.width || frameHeight != (size_t)motion.stored.height || bytesPerRow < frameWidth * 4
        || !CGRectContainsRect(frame, cut) || (over->blurred && !CGRectContainsRect(frame, over->soft))) {
        CVPixelBufferUnlockBaseAddress(buffer, 0);
        return NO;
    }
    if (over->blurred) {
        // An image counts its rows from the top, Core Graphics from the bottom.
        size_t top = (size_t)(motion.stored.height - CGRectGetMaxY(over->soft)), height = (size_t)over->soft.size.height;
        size_t width = (size_t)over->soft.size.width, rowBytes = width * 4;
        uint8_t *rows = base + top * bytesPerRow + (size_t)over->soft.origin.x * 4;
        // Accelerate's tent takes about 0.5 ms here up to 127 pixels across and some 40 times that past it.
        uint32_t kernel = MIN((uint32_t)(width * kSoftWidth) | 1, 127);
        // Read from the picture above and below the rows as far as the blur reaches, where the frame has it, so
        // their top and bottom are blurred with what is there rather than their edge drawn out.
        size_t above = MIN(kernel / 2, top), below = MIN(kernel / 2, frameHeight - top - height);
        vImage_Buffer from = {rows - above * bytesPerRow, height + above + below, width, bytesPerRow};
        vImage_Buffer to = {over->blurred, height, width, rowBytes};
        if (vImageTentConvolve_ARGB8888(&from, &to, NULL, 0, above, kernel, kernel, NULL, kvImageEdgeExtend) == kvImageNoError) {
            for (size_t y = 0; y < height; y++) {
                uint8_t *sharp = rows + y * bytesPerRow;
                const uint8_t *soft = over->blurred + y * rowBytes;
                uint16_t share = over->feather[y];
                if (share == 256) memcpy(sharp, soft, rowBytes);
                else if (share) for (size_t i = 0; i < rowBytes; i++) sharp[i] += (uint8_t)(((soft[i] - sharp[i]) * share) >> 8);
            }
        }
        if (!over->fitted) {
            // The luma (Rec. 709's weights on the stored values) the brightest tenth of the picture behind the
            // words reaches, as it shows there, softened.
            size_t histogram[256] = {0}, count = 0, seen = 0;
            for (size_t y = 0; y < height; y++) {
                const uint8_t *pixel = rows + y * bytesPerRow + (size_t)over->drawn.origin.x * 4;
                for (size_t x = 0; x < (size_t)over->drawn.size.width; x++, pixel += 4, count++)
                    histogram[(pixel[2] * 54 + pixel[1] * 183 + pixel[0] * 19) >> 8]++;
            }
            int light = 255;
            while (light > 0 && (seen += histogram[light]) < count / 10) light--;
            CGFloat band = MIN(MAX(1 - kBandLight * 255 / MAX(light, 1), kBandDim), kBandDarkest);
            setKeep(over, (size_t)cut.size.height, band);
            over->fitted = YES;
        }
    }
    // Blue and red, then green, each scaled in its own lane of the pixel; alpha is left as it is.
    size_t top = (size_t)cut.origin.y, width = (size_t)cut.size.width;
    for (size_t y = 0; y < (size_t)cut.size.height; y++) {
        uint32_t *pixel = (uint32_t *)(base + (top + y) * bytesPerRow) + (size_t)cut.origin.x, keep = over->keep[y];
        for (size_t x = 0; x < width; x++) {
            uint32_t v = pixel[x];
            pixel[x] = (((v & 0x00FF00FFu) * keep >> 8) & 0x00FF00FFu) | (((v & 0x0000FF00u) * keep >> 8) & 0x0000FF00u) | (v & 0xFF000000u);
        }
    }
    if (over->words) {
        CGContextRef context = newContext(motion.stored, base, bytesPerRow);
        CGContextDrawImage(context, CGRectOffset(over->drawn, cut.origin.x, cut.origin.y), over->words);
        CGContextRelease(context);
    }
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    return YES;
}

// Each frame of the video from `from` seconds (taken round its length) for `seconds`, round its end as often
// as needed, timed from 0, to `each`, which returns NO to stop. NO when a read failed.
static BOOL eachFrame(AVURLAsset *asset, AVAssetTrack *track, Motion motion, double from, double seconds,
                      BOOL (^each)(CMSampleBufferRef sample)) {
    int32_t scale = 600;   // a tick that 24, 25, 30 and 60 fps all land on
    double at = fmod(MAX(from, 0), motion.length), done = 0;
    // When the next frame is due: kMotionFPS on a schedule, so a 60 fps video keeps every other frame.
    double due = 0;
    while (seconds - done > 0.01) {
        double take = MIN(motion.length - at, seconds - done);
        AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:nil];
        AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:@{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        }];
        // Copies, so drawing into one never touches a frame the decoder still refers to.
        output.alwaysCopiesSampleData = YES;
        if (!reader || ![reader canAddOutput:output]) return NO;
        [reader addOutput:output];
        reader.timeRange = CMTimeRangeMake(CMTimeMakeWithSeconds(at, scale), CMTimeMakeWithSeconds(take, scale));
        if (![reader startReading]) return NO;
        CMSampleBufferRef sample;
        while ((sample = [output copyNextSampleBuffer])) {
            // The first frame may start before `at`; it shows from the start of this stretch.
            CMTime time = CMTimeMakeWithSeconds(done + MAX(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)) - at, 0), scale);
            CMSampleBufferRef timed = NULL;
            CMSampleTimingInfo timing = {kCMTimeInvalid, time, kCMTimeInvalid};
            BOOL keep = CMTimeGetSeconds(time) >= due - 0.002 && CMTimeGetSeconds(time) < done + take
                && CMSampleBufferGetImageBuffer(sample)
                && CMSampleBufferCreateCopyWithNewTiming(NULL, sample, 1, &timing, &timed) == noErr;
            CFRelease(sample);
            if (!keep) continue;
            // A jump in the video (its loop) starts the schedule again rather than keeping a burst of frames.
            due = due + 1.0 / kMotionFPS < CMTimeGetSeconds(time) ? CMTimeGetSeconds(time) + 0.5 / kMotionFPS : due + 1.0 / kMotionFPS;
            BOOL more = each(timed);
            CFRelease(timed);
            if (!more) {
                [reader cancelReading];
                return YES;
            }
        }
        if (reader.status != AVAssetReaderStatusCompleted) return NO;
        done += take;
        at = 0;
    }
    return YES;
}

CGImageRef SGLyricsClipMotionFrame(NSURL *motionFile, NSString *previous, NSString *line, NSString *translation, NSString *next,
                                   double from) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:motionFile options:nil];
    Motion motion;
    AVAssetTrack *track = motionTrack(asset, &motion);
    if (!track) return NULL;
    __block Over over = makeOver(motion, previous, line, translation, next);
    __block CGImageRef frame = NULL;
    eachFrame(asset, track, motion, from, motion.length, ^BOOL(CMSampleBufferRef sample) {
        CVPixelBufferRef buffer = CMSampleBufferGetImageBuffer(sample);
        if (!drawOver(buffer, motion, &over)) return NO;
        CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
        CGContextRef context = newContext(motion.stored, CVPixelBufferGetBaseAddress(buffer), CVPixelBufferGetBytesPerRow(buffer));
        CGImageRef whole = CGBitmapContextCreateImage(context);
        CGContextRelease(context);
        CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
        frame = CGImageCreateWithImageInRect(whole, cutIn(motion));
        CGImageRelease(whole);
        return NO;
    });
    freeOver(over);
    return frame;
}

BOOL SGLyricsClipWriteOverMotion(NSURL *file, NSURL *motionFile, NSString *previous, NSString *line, NSString *translation,
                                 NSString *next, double from, double seconds) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:motionFile options:nil];
    Motion motion;
    AVAssetTrack *track = motionTrack(asset, &motion);
    if (!track) return NO;
    // No longer than the video, which is then written whole and loops as it was made to.
    seconds = MIN(seconds, motion.length);
    NSURL *partial = [file URLByAppendingPathExtension:@"partial"];
    [NSFileManager.defaultManager removeItemAtURL:partial error:nil];
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:partial fileType:AVFileTypeMPEG4 error:nil];
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @(motion.cut.width),
        AVVideoHeightKey: @(motion.cut.height),
        AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
        // As SGMotionClip.m's cut: about 2 Mbit/s at a Canvas's 720 x 960.
        AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: @(motion.cut.width * motion.cut.height * 3)},
    }];
    if (!writer || ![writer canAddInput:input]) return NO;
    [writer addInput:input];
    if (![writer startWriting]) return NO;
    [writer startSessionAtSourceTime:kCMTimeZero];
    __block Over over = makeOver(motion, previous, line, translation, next);
    __block BOOL ok = YES, any = NO;
    BOOL read = eachFrame(asset, track, motion, from, seconds, ^BOOL(CMSampleBufferRef sample) {
        if (!drawOver(CMSampleBufferGetImageBuffer(sample), motion, &over)) {
            ok = NO;
            return NO;
        }
        while (!input.readyForMoreMediaData && writer.status == AVAssetWriterStatusWriting) [NSThread sleepForTimeInterval:0.002];
        ok = writer.status == AVAssetWriterStatusWriting && [input appendSampleBuffer:sample];
        any = YES;
        return ok;
    });
    freeOver(over);
    if (!read || !ok || !any) {
        [writer cancelWriting];
        return NO;
    }
    [input markAsFinished];
    [writer endSessionAtSourceTime:CMTimeMakeWithSeconds(seconds, 600)];
    dispatch_semaphore_t written = dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(written); }];
    dispatch_semaphore_wait(written, DISPATCH_TIME_FOREVER);
    if (writer.status != AVAssetWriterStatusCompleted) return NO;
    [NSFileManager.defaultManager removeItemAtURL:file error:nil];
    return [NSFileManager.defaultManager moveItemAtURL:partial toURL:file error:nil];
}

NSString *SGLyricsClipLook(NSURL *motion, SGLyricsClipStyle style) {
    if (!motion) return [NSString stringWithFormat:@"%ld", (long)style];
    NSString *name = motion.lastPathComponent.stringByDeletingPathExtension;
    return [NSString stringWithFormat:@"m%@s%ld", name.length > 16 ? [name substringToIndex:16] : name, (long)style];
}
