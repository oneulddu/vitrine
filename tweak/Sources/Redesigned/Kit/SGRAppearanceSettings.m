#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "SGRAccent.h"
#import "SGRHeaderInfo.h"

// The preset is read off the color stored, so the hooks keep the one key they read and a color set before
// presets existed stays in effect: Apple Music's red reads as Apple Music, Spotify's own (-1) as Spotify, and
// any other color as Custom, the redesign's own green when nothing is stored among them. The custom color
// is put aside while a preset is in place, so Custom brings it back.
static NSArray<NSString *> *presets(void) {
    return @[@"Spotify", @"Apple Music", SGL(@"settings.appearance.accent.choice.custom", @"Custom")];
}

static NSInteger preset(void) {
    NSInteger rgb = SGInt(SGRKeyAccent, SGRDefaultAccent);
    if (rgb < 0 || rgb > 0xFFFFFF) return 0;
    return rgb == SGAppleMusicRed ? 1 : 2;
}

static void choosePreset(NSInteger index) {
    if (preset() == 2) SGSetInt(SGRKeyAccentCustom, SGRAccentRGB());
    NSInteger custom = SGInt(SGRKeyAccentCustom, SGRDefaultAccent);
    if (custom < 0 || custom > 0xFFFFFF) custom = SGRDefaultAccent;
    SGSetInt(SGRKeyAccent, index == 0 ? -1 : index == 1 ? SGAppleMusicRed : custom);
}

// A color from the sheet, a swatch's or the picker's: Custom, and first among the recent colors when it is another.
static void chooseColor(NSInteger rgb) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    NSArray<NSNumber *> *recent = SGRAccentRecentFrom([store objectForKey:SGRKeyAccentRecent]);
    [store setObject:SGRAccentRecentAdding(recent, rgb, SGRAccentRGB()) forKey:SGRKeyAccentRecent];
    SGSetInt(SGRKeyAccent, rgb);
    SGSetInt(SGRKeyAccentCustom, rgb);
}

// The redesign's rows of the Appearance page (App/Pages.m): the preset from a menu, then the color in effect,
// which opens the sheet of recent colors and the picker; a color stored from there is Custom. AMOLED has no row:
// the redesign is always black.
NSArray<SGModRow *> *SGRAppearanceRows(void) {
    SGModRow *menu = SGMenuRow(SGL(@"settings.appearance.accent_preset.title", @"Accent color preset"), presets(), ^NSString *{ return presets()[(NSUInteger)preset()]; },
                               ^(NSInteger index) { choosePreset(index); });
    SGModRow *colour = SGStatActionRow(SGL(@"settings.appearance.accent_color.title", @"Accent color"), nil, ^NSString *{ return [NSString stringWithFormat:@"#%06lX", (long)SGRAccentRGB()]; }, ^{
        SGRPickAccent(SGL(@"settings.appearance.accent_picker.title", @"Accent color"), SGRAccentRGB(),
                      SGRAccentRecentFrom([NSUserDefaults.standardUserDefaults objectForKey:SGRKeyAccentRecent]), ^(NSInteger rgb) { chooseColor(rgb); });
    });
    colour.swatch = ^UIColor *{ return SGColorRGB(SGRAccentRGB()); };
    return @[
        SGWithSymbol(menu, @"paintpalette"),
        SGWithSymbol(colour, @"eyedropper"),
        SGWithSymbol(SGOptionRow(SGL(@"settings.appearance.plain_checkmark.title", @"Plain checkmark"), SGL(@"settings.appearance.plain_checkmark.subtitle", @"A saved song's tick without its circle, in the accent"), SGRKeyPlainCheck), @"checkmark"),
        SGWithSymbol(SGSwitchRow(SGL(@"settings.appearance.full_bleed.title", @"Full bleed covers"), SGL(@"settings.appearance.full_bleed.subtitle", @"Album and playlist covers across the top. Off, a square cover; an animated cover still fills the top"), SGRKeyFullBleedCovers), @"photo"),
    ];
}
