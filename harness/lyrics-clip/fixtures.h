// The stand-in cover and the lines main.m renders in every layout, shared with frames.m (unchanged.sh).
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

// A stand-in cover: two colored halves and a light disc, so the blur and the darkening show.
static inline CGImageRef newCover(void) {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(NULL, 640, 640, 8, 0, space, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGContextSetRGBFillColor(context, 0.9, 0.3, 0.2, 1);
    CGContextFillRect(context, CGRectMake(0, 0, 640, 320));
    CGContextSetRGBFillColor(context, 0.2, 0.4, 0.9, 1);
    CGContextFillRect(context, CGRectMake(0, 320, 640, 320));
    CGContextSetRGBFillColor(context, 0.95, 0.9, 0.7, 1);
    CGContextFillEllipseInRect(context, CGRectMake(200, 200, 240, 240));
    CGImageRef cover = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    return cover;
}

// name, line, its translation, next
static inline NSArray<NSArray<NSString *> *> *clipCases(void) {
    return @[
        @[@"short", @"Hold on", @"", @"we're almost there"],
        @[@"long", @"And every word I never said keeps ringing out across the quiet of the night", @"", @"until the morning finds us"],
        @[@"cjk", @"夜空に光る星を数えながら", @"", @"君の名前を呼んだ"],
        @[@"translated", @"夜空に光る星を数えながら", @"밤하늘에 빛나는 별을 세면서", @"君の名前を呼んだ"],
        @[@"translated-long", @"And every word I never said keeps ringing out across the quiet of the night",
          @"내가 하지 못한 모든 말들이 고요한 밤을 가로질러 계속 울려 퍼져", @"until the morning finds us"],
        @[@"break", @"", @"번역만 있는 쉼", @"The first line, coming up"],
        @[@"last", @"The very last line", @"", @""],
        @[@"empty", @"", @"", @""],
        // Too tall even at the smallest size: the next line and the translation go, and the line ends in an ellipsis.
        @[@"overflow", [@"" stringByPaddingToLength:900 withString:@"Every word I never said keeps ringing out across the quiet night, " startingAtIndex:0],
          [@"" stringByPaddingToLength:300 withString:@"and every promise I forgot comes back to find me here again, " startingAtIndex:0],
          @"until the morning finds us"],
        @[@"overflow-cjk", [@"" stringByPaddingToLength:420 withString:@"夜空に光る星を数えながら君の名前を何度も呼んだ、" startingAtIndex:0],
          [@"" stringByPaddingToLength:200 withString:@"밤하늘에 빛나는 별을 세면서 너의 이름을 몇 번이고 불렀어, " startingAtIndex:0],
          @"君の名前を呼んだ"],
    ];
}
