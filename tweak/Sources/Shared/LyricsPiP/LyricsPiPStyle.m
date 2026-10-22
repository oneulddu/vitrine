#import "LyricsPiPStyle.h"
#import "Core/SGCore.h"
#import "Shared/Fonts/Fonts.h"
#import "Shared/Fonts/FontLibrary.h"
#import <math.h>

@implementation SGLyricsPiPStyle
- (CGSize)raster {
    return _layout == 1 ? CGSizeMake(800, 450) : _layout == 2 ? CGSizeMake(480, 720) : CGSizeMake(640, 640);
}
- (NSArray *)identity {
    return @[@(_layout), @(_alignment), @(_info), _font ?: @"system", _sizes, _weights];
}
@end

NSString *SGLyricsPiPRoleKey(NSUInteger role, NSString *field) {
    return [NSString stringWithFormat:@"spotifyglass.lyrics.pip.%@.%@",
        @[@"original", @"pronunciation", @"translation"][MIN(role, 2)], field];
}
static double number(NSString *key, double fallback, double low, double high) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    double n = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
    return isfinite(n) ? MIN(high, MAX(low, n)) : fallback;
}
static NSString *appFont(void) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    switch (SGAppFontChosen()) {
        case SGAppFontSystem: return @"system";
        case SGAppFontRounded: return @"rounded";
        case SGAppFontSerif: return @"serif";
        case SGAppFontMono: return @"mono";
        case SGAppFontCustom: return SGRegisterCustomFont() ?: @"system";
        case SGAppFontFamily: return [d stringForKey:SGKeyAppFontFamily] ?: @"system";
        case SGAppFontLibrary: return SGFontLibraryRegister([d stringForKey:SGKeyAppFontLibrary]) ?: @"system";
        default: return @"Spotify Mix UI";
    }
}
static NSString *resolvedFont(NSString *font) {
    static NSArray *key;
    static NSString *resolved;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:SGFontLibraryChangedNotification object:nil queue:nil
            usingBlock:^(NSNotification *note) { key = nil; }]; // FontLibrary documents main-thread delivery.
    });
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSArray *next = @[font, @(SGAppFontChosen()), [d objectForKey:SGKeyAppFontFiles] ?: @[],
        [d stringForKey:SGKeyAppFontName] ?: @"", [d stringForKey:SGKeyAppFontLibrary] ?: @"",
        [d stringForKey:SGKeyAppFontFamily] ?: @""];
    if (![key isEqual:next]) {
        key = next;
        resolved = [font isEqual:@"app"] ? appFont() :
            [font isEqual:@"custom"] ? SGRegisterCustomFont() :
            [font hasPrefix:@"library:"] ? SGFontLibraryRegister([font substringFromIndex:8]) : font;
    }
    return resolved ?: @"system";
}
SGLyricsPiPStyle *SGLyricsPiPReadStyle(void) {
    SGLyricsPiPStyle *s = [SGLyricsPiPStyle new];
    s.layout = number(SGKeyPiPLayout, 0, 0, 2);
    s.alignment = number(SGKeyPiPAlignment, 1, 0, 2);
    s.info = number(SGKeyPiPInfo, 1, 0, 1) != 0;
    NSString *font = [NSUserDefaults.standardUserDefaults stringForKey:SGKeyPiPFont] ?: @"app";
    s.font = resolvedFont(font);
    NSMutableArray *sizes = [NSMutableArray array], *weights = [NSMutableArray array];
    for (NSUInteger i = 0; i < 3; i++) {
        [sizes addObject:@(number(SGLyricsPiPRoleKey(i, @"size"), i == 0 ? 40 : 26, i == 0 ? 24 : 16, i == 0 ? 64 : 48))];
        [weights addObject:@(number(SGLyricsPiPRoleKey(i, @"weight"), i == 0 ? 2 : 0, 0, 3))];
    }
    s.sizes = sizes; s.weights = weights;
    return s;
}
void SGLyricsPiPResetStyle(void) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    for (NSString *key in @[SGKeyPiPLayout, SGKeyPiPAlignment, SGKeyPiPInfo, SGKeyPiPFont]) [d removeObjectForKey:key];
    for (NSUInteger i = 0; i < 3; i++)
        for (NSString *field in @[@"size", @"weight"]) [d removeObjectForKey:SGLyricsPiPRoleKey(i, field)];
}
NSArray<NSString *> *SGLyricsPiPFontChoices(void) {
    NSMutableArray *choices = [NSMutableArray arrayWithArray:@[@"app", @"system", @"rounded", @"serif", @"mono"]];
    [choices addObjectsFromArray:SGAppFontFamilies()];
    NSString *custom = SGRegisterCustomFont();
    if (custom) [choices addObject:@"custom"];
    for (SGLibraryFont *font in SGFontLibrary()) {
        if (!SGFontLibraryInstalled(font.identifier)) continue;
        NSString *family = SGFontLibraryRegister(font.identifier);
        if (family) [choices addObject:[@"library:" stringByAppendingString:font.identifier]];
    }
    return choices;
}
NSString *SGLyricsPiPFontName(NSString *identifier) {
    if ([identifier isEqual:@"app"]) return SGL(@"settings.lyrics.pip.font.app", @"App font");
    if ([identifier isEqual:@"system"]) return @"San Francisco";
    if ([identifier isEqual:@"rounded"]) return @"SF Rounded";
    if ([identifier isEqual:@"serif"]) return @"New York";
    if ([identifier isEqual:@"mono"]) return @"SF Mono";
    if ([identifier isEqual:@"custom"]) return SGRegisterCustomFont() ?: SGL(@"settings.lyrics.pip.font.imported", @"Imported font");
    if ([identifier hasPrefix:@"library:"]) return SGFontLibraryFont([identifier substringFromIndex:8]).name ?: @"San Francisco";
    return identifier;
}
CTFontRef SGLyricsPiPCreateFont(SGLyricsPiPStyle *style, NSUInteger role, CGFloat size) {
    CGFloat weight = role < 3 ? (CGFloat[]){0, .23, .3, .4}[MIN(3, style.weights[role].unsignedIntegerValue)] : 0;
    NSString *family = style.font;
    NSDictionary *designs = @{@"system": UIFontDescriptorSystemDesignDefault, @"rounded": UIFontDescriptorSystemDesignRounded,
        @"serif": UIFontDescriptorSystemDesignSerif, @"mono": UIFontDescriptorSystemDesignMonospaced};
    CTFontRef system = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, size, NULL);
    CTFontDescriptorRef descriptor = NULL;
    if (!designs[family] && ![UIFont fontNamesForFamilyName:family].count) family = @"system";
    if (designs[family]) {
        // Start in Core Text, not the app-wide hooked UIFont systemFont API.
        UIFontDescriptor *ui = [(__bridge UIFont *)system fontDescriptor];
        ui = [ui fontDescriptorWithDesign:designs[family]] ?: ui;
        descriptor = CTFontDescriptorCreateCopyWithAttributes((__bridge CTFontDescriptorRef)ui,
            (__bridge CFDictionaryRef)@{(__bridge NSString *)kCTFontTraitsAttribute: @{(__bridge NSString *)kCTFontWeightTrait: @(weight)}});
    } else {
        descriptor = CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef)@{
            (__bridge NSString *)kCTFontFamilyNameAttribute: family ?: @"",
            (__bridge NSString *)kCTFontTraitsAttribute: @{(__bridge NSString *)kCTFontWeightTrait: @(weight),
                (__bridge NSString *)kCTFontSlantTrait: @0}});
    }
    CTFontRef font = CTFontCreateWithFontDescriptor(descriptor, size, NULL);
    CFRelease(descriptor);
    CFRelease(system);
    return font;
}
