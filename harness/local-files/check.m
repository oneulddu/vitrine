// Checks LocalFiles.m as the tweak compiles it: a URI read back into names, an edit laid over them, the
// lyrics key an edit gives (a new one for a rename only), and a stored cover's address and its way back.
// Runs in its own defaults domain and Application Support, so nothing of the Mac's is touched. Exits
// non-zero on the first wrong answer.
#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>
#import "Shared/LocalFiles/LocalFiles.h"

#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #cond); exit(1); } } while (0)

static UIImage *square(void) {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(4, 4)] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.redColor setFill];
        UIRectFill(CGRectMake(0, 0, 4, 4));
    }];
}

static void coverImportChecks(void) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = YES;
    UIImage *large = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(2400, 1200) format:format]
        imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [UIColor.redColor setFill]; UIRectFill(CGRectMake(0, 0, 2400, 1200));
            [UIColor.blueColor setFill]; UIRectFill(CGRectMake(1200, 0, 1200, 1200));
        }];
    for (NSNumber *orientation in @[@(UIImageOrientationUp), @(UIImageOrientationUpMirrored),
                                    @(UIImageOrientationRight), @(UIImageOrientationLeft)]) {
        UIImage *original = [UIImage imageWithCGImage:large.CGImage scale:1 orientation:orientation.integerValue];
        __block UIImage *thumbnail;
        dispatch_sync(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            thumbnail = SGLocalFileThumbnail(original);
        });
        BOOL rotated = orientation.integerValue == UIImageOrientationRight || orientation.integerValue == UIImageOrientationLeft;
        CHECK(thumbnail && CGImageGetWidth(thumbnail.CGImage) == (rotated ? 600 : 1200));
        CHECK(CGImageGetHeight(thumbnail.CGImage) == (rotated ? 1200 : 600));
        CHECK(thumbnail.imageOrientation == UIImageOrientationUp);
        if (!rotated) {
            // Sample the left quarter in an explicitly RGBA bitmap: mirroring must change red to blue.
            uint8_t pixel[4] = {0};
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            CGContextRef context = CGBitmapContextCreate(pixel, 1, 1, 8, 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
            CHECK(context);
            CGContextDrawImage(context, CGRectMake(-300, -300, 1200, 600), thumbnail.CGImage);
            CGContextRelease(context);
            CGColorSpaceRelease(space);
            if (orientation.integerValue == UIImageOrientationUpMirrored) CHECK(pixel[0] == 0 && pixel[2] == 255);
            else CHECK(pixel[0] == 255 && pixel[2] == 0);
        }
    }
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"jpg"]]];
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, CFSTR("public.jpeg"), 1, NULL);
    CHECK(destination);
    CGImageDestinationAddImage(destination, large.CGImage, (__bridge CFDictionaryRef)@{(id)kCGImagePropertyOrientation: @6});
    CHECK(CGImageDestinationFinalize(destination));
    CFRelease(destination);
    __block UIImage *preview;
    dispatch_sync(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ preview = SGLocalFileReadCover(url); });
    CHECK(preview && CGImageGetWidth(preview.CGImage) == 600 && CGImageGetHeight(preview.CGImage) == 1200);
    CHECK(preview.imageOrientation == UIImageOrientationUp);
    CHECK([@"not an image" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    dispatch_sync(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ preview = SGLocalFileReadCover(url); });
    CHECK(!preview);
    CHECK([NSFileManager.defaultManager removeItemAtURL:url error:nil]);
}

int main(void) {
    @autoreleasepool {
        coverImportChecks();
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyLocalFileEdits];
        NSString *uri = @"spotify:local:Daft+Punk:Discovery:One+More+Time%3A+Remix:320";

        // The URI's own names, form decoded, and the bare URI as the key.
        NSDictionary *tags = SGLocalFileTags(uri);
        CHECK([tags[@"title"] isEqualToString:@"One More Time: Remix"] && [tags[@"artist"] isEqualToString:@"Daft Punk"]);
        CHECK([tags[@"seconds"] integerValue] == 320);
        CHECK([SGLocalFileLyricsKey(uri) isEqualToString:uri]);
        CHECK(!SGLocalFileLyricsKey(@"spotify:track:4uLU6hMCjMI75M1A2tKUQC"));

        // A cover alone keeps the key: no rename, so the lyrics stay where they are.
        SGLocalFileSaveEdit(uri, @{@"title": @"One More Time: Remix", @"artist": @"", @"album": @"Discovery"}, square(), YES);
        NSDictionary *edit = SGLocalFileEditFor(uri);
        CHECK(edit[@"cover"] && !edit[@"number"] && !edit[@"title"]);
        CHECK([SGLocalFileLyricsKey(uri) isEqualToString:uri]);
        NSString *cover = SGLocalFileCoverPath(edit);
        CHECK([NSFileManager.defaultManager fileExistsAtPath:cover]);
        CHECK([SGLocalFileCoverInURL(SGLocalFileCoverURL(cover)) isEqualToString:cover]);
        CHECK(![SGLocalFileCoverURL(cover) containsString:@"/"]);
        CHECK(!SGLocalFileCoverInURL(@"spotify:localfileimage:%2Fetc%2Fpasswd"));

        // A rename gives a new key, and the names reach the sources through it.
        SGLocalFileSaveEdit(uri, @{@"title": @"One More Time", @"artist": @"Daft Punk"}, nil, YES);
        edit = SGLocalFileEditFor(uri);
        NSString *renamed = SGLocalFileLyricsKey(uri);
        CHECK(edit[@"number"] && edit[@"cover"] && [renamed hasPrefix:[uri stringByAppendingString:@"#"]]);
        CHECK([SGLocalFileInfo(renamed)[@"title"] isEqualToString:@"One More Time"]);
        CHECK([SGLocalFileInfo(renamed)[@"seconds"] integerValue] == 320);

        // The same names saved again, or a new cover with them, keep that key.
        [NSThread sleepForTimeInterval:0.01];
        SGLocalFileSaveEdit(uri, @{@"title": @"One More Time ", @"artist": @"Daft Punk"}, nil, YES);
        CHECK([SGLocalFileLyricsKey(uri) isEqualToString:renamed]);
        SGLocalFileSaveEdit(uri, @{@"title": @"One More Time"}, square(), YES);
        CHECK([SGLocalFileLyricsKey(uri) isEqualToString:renamed]);
        CHECK(![NSFileManager.defaultManager fileExistsAtPath:cover]);   // the replaced cover is gone
        cover = SGLocalFileCoverPath(SGLocalFileEditFor(uri));

        // Another rename, another key.
        [NSThread sleepForTimeInterval:0.01];
        SGLocalFileSaveEdit(uri, @{@"title": @"One More Time (Live)"}, nil, YES);
        NSString *again = SGLocalFileLyricsKey(uri);
        CHECK(![again isEqualToString:renamed] && [again hasPrefix:uri]);

        // Back to the file's own names with the cover kept: the bare URI again.
        SGLocalFileSaveEdit(uri, @{@"title": @"One More Time: Remix"}, nil, YES);
        CHECK([SGLocalFileLyricsKey(uri) isEqualToString:uri] && SGLocalFileEditFor(uri)[@"cover"]);

        // Nothing left over: the edit and its cover go.
        SGLocalFileSaveEdit(uri, @{}, nil, NO);
        CHECK(!SGLocalFileEditFor(uri) && ![NSFileManager.defaultManager fileExistsAtPath:cover]);
        CHECK(!SGLocalFileInfo(@"spotify:local:too:few:parts"));
        printf("local files: all checks passed\n");
    }
    return 0;
}
