// Historical comparison tool (not a current acceptance gate): `write <dir>` saves every fixture in Left, Centered and
// Poster as raw RGBA, `check <dir>` draws them again and fails on any pixel that differs. Built with -DSG_BASELINE
// against SGLyricsClip.m as it was before Messages and Vinyl, in its signature then; built without, against today's,
// with the scenes' inputs (the cover and the line sung last) handed over too, which those three layouts must leave out.
#import <Foundation/Foundation.h>
#import "Shared/LockScreenLyrics/SGLyricsClip.h"
#import "fixtures.h"

static NSData *rgba(CGImageRef image) {
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    NSMutableData *data = [NSMutableData dataWithLength:width * height * 4];
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(data.mutableBytes, width, height, 8, width * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    return data;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 3 || (strcmp(argv[1], "write") && strcmp(argv[1], "check"))) {
            fprintf(stderr, "usage: %s write|check <dir>\n", argv[0]);
            return 2;
        }
        BOOL writing = !strcmp(argv[1], "write");
        NSString *dir = [NSString stringWithUTF8String:argv[2]];
        CGImageRef cover = newCover();
        CGSize size = SGLyricsClipSize(1206);
        CGImageRef backdrop = SGLyricsClipBackdrop(cover, size);
        NSArray *layoutNames = @[@"left", @"centered", @"poster"];
        int failures = 0;
        for (SGLyricsClipLayout layout = SGLyricsClipLeft; layout <= SGLyricsClipPoster; layout++) {
            for (NSArray *c in clipCases()) @autoreleasepool {
                NSString *line = [c[1] length] ? c[1] : nil, *translation = [c[2] length] ? c[2] : nil, *next = [c[3] length] ? c[3] : nil;
#ifdef SG_BASELINE
                CGImageRef frame = SGLyricsClipFrameWithLayout(backdrop, line, translation, next, size, layout);
#else
                CGImageRef frame = SGLyricsClipFrameWithLayout(backdrop, cover, @"The line sung before", line, translation, next, size,
                                                               layout);
#endif
                NSString *name = [NSString stringWithFormat:@"%@-%@", c[0], layoutNames[layout]];
                NSString *path = [[dir stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"rgba"];
                NSData *pixels = rgba(frame);
                CGImageRelease(frame);
                if (writing) {
                    if (![pixels writeToFile:path atomically:YES]) {
                        printf("  FAIL %s not written\n", name.UTF8String);
                        failures++;
                    }
                    continue;
                }
                NSData *before = [NSData dataWithContentsOfFile:path];
                size_t differ = 0;
                if (before.length == pixels.length) {
                    const uint8_t *a = before.bytes, *b = pixels.bytes;
                    for (size_t i = 0; i < pixels.length; i += 4) differ += memcmp(a + i, b + i, 4) != 0;
                }
                BOOL ok = before.length == pixels.length && !differ;
                printf("  %s %s draws as before (%zu pixels differ)\n", ok ? "ok  " : "FAIL", name.UTF8String,
                       before.length == pixels.length ? differ : (size_t)(pixels.length / 4));
                if (!ok) failures++;
            }
        }
        CGImageRelease(backdrop);
        CGImageRelease(cover);
        if (!writing) printf("%s\n", failures ? "Left, Centered and Poster CHANGED" : "Left, Centered and Poster unchanged");
        return failures ? 1 : 0;
    }
}
