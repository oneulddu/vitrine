#import "LyricsBackgroundSettings.h"
#import "LyricsBackground.h"
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"

NSArray<SGModRow *> *SGLyricsBackgroundRows(NSString *prefix) {
    SGModRow *mode = SGChoiceRow(SGL(@"settings.background.mode.title", @"Background"), nil,
        [prefix stringByAppendingString:@".mode"], @[
            SGL(@"settings.background.mode.cover", @"Clear album cover"),
            SGL(@"settings.background.mode.monochrome", @"Monochrome album cover"),
            SGL(@"settings.background.mode.blur", @"Blurred album cover"),
            SGL(@"settings.background.mode.gradient", @"Album-color gradient"),
            SGL(@"settings.background.mode.solid", @"Solid color")], SGLyricsBackgroundCover);
    SGModRow *darkness = SGSliderRow(SGL(@"settings.background.darkness.title", @"Darken background"),
        SGL(@"settings.background.darkness.subtitle", @"Keeps lyrics readable without hiding album details."),
        0, 85, 1, ^double { return SGLyricsBackgroundRead(prefix).darkness * 100; },
        ^(double value) { [NSUserDefaults.standardUserDefaults setDouble:value forKey:[prefix stringByAppendingString:@".darkness"]]; },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f%%", value]; });
    SGModRow *blur = SGSliderRow(SGL(@"settings.background.blur.title", @"Blur strength"),
        SGL(@"settings.background.blur.subtitle", @"Only applies to the blurred album cover."),
        0, 40, 1, ^double { return SGLyricsBackgroundRead(prefix).blur; },
        ^(double value) { [NSUserDefaults.standardUserDefaults setDouble:value forKey:[prefix stringByAppendingString:@".blur"]]; },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f", value]; });
    blur.visible = ^BOOL { return SGLyricsBackgroundRead(prefix).mode == SGLyricsBackgroundBlur; };
    NSString *colorTitle = SGL(@"settings.background.color.title", @"Background color");
    SGModRow *color = SGStatActionRow(colorTitle,
        SGL(@"settings.background.color.subtitle", @"Only applies to the solid background."),
        ^NSString *{ return [NSString stringWithFormat:@"#%06X", SGLyricsBackgroundRead(prefix).color]; }, ^{
            SGPickColor(colorTitle, SGLyricsBackgroundRead(prefix).color, ^(NSInteger rgb) {
                [NSUserDefaults.standardUserDefaults setInteger:rgb forKey:[prefix stringByAppendingString:@".color"]];
            });
        });
    color.swatch = ^UIColor *{ return SGColorRGB(SGLyricsBackgroundRead(prefix).color); };
    color.visible = ^BOOL { return SGLyricsBackgroundRead(prefix).mode == SGLyricsBackgroundSolid; };
    return @[mode, darkness, blur, color];
}
