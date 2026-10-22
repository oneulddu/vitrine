// Only the settings framework's storage containers are mocked; both row builders are production.
#import "tests.h"
#import "Settings/SGModPage.h"
#import "Shared/LyricsPiP/LyricsPiP.h"
#import "Shared/LyricsBackground/LyricsBackground.h"
@implementation SGPage
@end
@implementation SGModRow
@end
@implementation SGModSection
@end
@implementation SGModPage
- (instancetype)initWithTitle:(NSString *)title intro:(NSString *)intro sections:(NSArray *)sections footer:(NSString *)footer {
    if ((self = [super init])) { self.title = title; _sections = sections; }
    return self;
}
- (void)refreshVisibility {}
- (void)revealRowTitled:(NSString *)title {}
@end
SGModRow *SGPageRow(NSString *title, UIViewController *(^page)(void)) {
    SGModRow *row = [SGModRow new]; row.title = title; row.page = page; return row;
}
SGModRow *SGOptionRow(NSString *title, NSString *subtitle, NSString *key) {
    SGModRow *row = [SGModRow new]; row.title = title; row.subtitle = subtitle; row.key = key; return row;
}
SGModSection *SGSection(NSString *title, NSArray *rows) {
    SGModSection *section = [SGModSection new]; section.title = title; section.rows = rows; return section;
}
SGModRow *SGChoiceRow(NSString *title, NSString *subtitle, NSString *key, NSArray *choices, NSInteger fallback) {
    SGModRow *row = SGOptionRow(title, subtitle, key); row.menu = choices; return row;
}
SGModRow *SGSliderRow(NSString *title, NSString *subtitle, double min, double max, double step,
    double (^get)(void), void (^set)(double), NSString *(^format)(double)) {
    SGModRow *row = [SGModRow new]; row.title = title; row.subtitle = subtitle;
    row.minimum = min; row.maximum = max; row.step = step; row.number = get; row.setNumber = set; row.format = format; return row;
}
SGModRow *SGStatActionRow(NSString *title, NSString *subtitle, NSString *(^value)(void), void (^action)(void)) {
    SGModRow *row = [SGModRow new]; row.title = title; row.subtitle = subtitle; row.value = value; row.action = action; return row;
}
void SGPickColor(NSString *title, NSInteger initial, void (^picked)(NSInteger)) { picked(0x123456); }
UIColor *SGColorRGB(NSInteger rgb) { return UIColor.blackColor; }

void SGTestSettings(void) {
    SGModRow *link = SGLyricsPiPRow();
    SGTestAssert(link.page && !link.key && [link.subtitle isEqual:@"Open lyrics over other apps and customize their background."],
        @"existing settings-row API now returns discoverable page link");
    SGModPage *page = (id)link.page();
    SGModRow *toggle = page.sections[0].rows[0];
    SGTestAssert([toggle.key isEqual:SGKeyLyricsPiP] && [toggle.subtitle containsString:@"Restart Spotify"],
        @"page preserves opt-in toggle and existing restart explanation");
    NSArray<SGModRow *> *rows = page.sections[1].rows;
    SGTestAssert(rows.count == 4 && [rows[0].key isEqual:@"spotifyglass.lyrics.pip.background.mode"] && rows[0].menu.count == 5,
        @"page reuses all five shared background choices under PiP prefix");
    SGTestAssert(rows[1].minimum == 0 && rows[1].maximum == 85 && rows[2].minimum == 0 && rows[2].maximum == 40,
        @"darkness and blur expose exact slider ranges");
    // Restore the persistent harness domain after exercising the actual setters.
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *darkness = @"spotifyglass.lyrics.pip.background.darkness", *blur = @"spotifyglass.lyrics.pip.background.blur";
    NSString *color = @"spotifyglass.lyrics.pip.background.color";
    NSString *domain = NSProcessInfo.processInfo.processName;
    NSDictionary *saved = [defaults persistentDomainForName:domain] ?: @{};
    SGTestSetting(darkness, nil);
    rows[1].setNumber(33);
    rows[2].setNumber(12);
    rows[3].action();
    SGTestAssert(rows[1].number() == 33 && rows[2].number() == 12 && SGLyricsBackgroundRead(@"spotifyglass.lyrics.pip.background").color == 0x123456
        && SGLyricsBackgroundRead(@"spotifyglass.lockscreen.background").darkness == .8,
        @"production slider/color writes never change lockscreen preferences");
    [defaults setPersistentDomain:saved forName:domain];
    // These keys were created only by this host test when Foundation uses its executable domain.
    for (NSString *key in @[darkness, blur, color])
        if (!saved[key]) [defaults removeObjectForKey:key]; else [defaults setObject:saved[key] forKey:key];
    SGTestSetting(darkness, @45);
    SGTestSetting(@"spotifyglass.lyrics.pip.background.mode", @2);
    SGTestAssert(rows[2].visible() && !rows[3].visible(), @"blur control shown only in blur mode");
    SGTestSetting(@"spotifyglass.lyrics.pip.background.mode", @4);
    SGTestAssert(!rows[2].visible() && rows[3].visible(), @"color control shown only in solid mode");
    SGTestSetting(@"spotifyglass.lyrics.pip.background.mode", @0);
}
