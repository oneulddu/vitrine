#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "LyricsPiP.h"
#import "LyricsPiPBackground.h"
#import "Shared/LyricsBackground/LyricsBackgroundSettings.h"
#import "LyricsPiPFrame.h"
#import "Shared/Fonts/FontLibrary.h"

// SGModPage remains the native grouped settings page; its header is a real CPU-rendered frame.
@interface SGLyricsPiPSettingsPage : SGModPage
@property (nonatomic, strong) UIImageView *preview;
@property (nonatomic, strong) UILabel *sampleLabel;
@end
@implementation SGLyricsPiPSettingsPage
- (void)viewDidLoad {
    [super viewDidLoad];
    self.preview = [UIImageView new];
    self.preview.contentMode = UIViewContentModeScaleAspectFit;
    self.preview.isAccessibilityElement = YES;
    self.preview.accessibilityLabel = SGL(@"settings.lyrics.pip.preview", @"Sample preview");
    self.sampleLabel = [UILabel new];
    self.sampleLabel.text = self.preview.accessibilityLabel;
    self.sampleLabel.textColor = UIColor.secondaryLabelColor;
    self.sampleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.sampleLabel.textAlignment = NSTextAlignmentCenter;
    UIView *header = [UIView new];
    [header addSubview:self.preview]; [header addSubview:self.sampleLabel];
    self.tableView.tableHeaderView = header;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(previewChanged:)
        name:NSUserDefaultsDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(previewChanged:)
        name:SGFontLibraryChangedNotification object:nil];
    [self updatePreview];
}
- (void)previewChanged:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{ [self updatePreview]; [self refreshVisibility]; });
}
- (void)updatePreview {
    NSArray *sample = @[SGL(@"settings.lyrics.pip.sample.original", @"별빛을 따라 걸어요"),
        SGL(@"settings.lyrics.pip.sample.next", @"A new day is on its way"),
        SGL(@"settings.lyrics.pip.sample.credit", @"Sample lyrics · Vitrine"),
        @"Byeolbicheul ttara georeoyo", @"We walk beneath the stars",
        SGL(@"settings.lyrics.pip.sample.song", @"A song for the night"), @"Vitrine"];
    self.preview.image = [UIImage imageWithData:SGLyricsPiPFramePNG(sample)];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header = self.tableView.tableHeaderView;
    CGFloat width = self.tableView.bounds.size.width;
    if (!header || width <= 0) return;
    self.preview.frame = CGRectMake(20, 8, MAX(0, width - 40), 220);
    self.sampleLabel.frame = CGRectMake(20, 232, MAX(0, width - 40), 24);
    if (header.frame.size.height != 268 || header.frame.size.width != width) {
        header.frame = CGRectMake(0, 0, width, 268);
        self.tableView.tableHeaderView = header;
    }
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end

static NSArray *weights(void) {
    return @[SGL(@"settings.lyrics.pip.weight.regular", @"Regular"),
        SGL(@"settings.lyrics.pip.weight.medium", @"Medium"),
        SGL(@"settings.lyrics.pip.weight.semibold", @"Semibold"),
        SGL(@"settings.lyrics.pip.weight.bold", @"Bold")];
}
static SGModRow *fontRow(void) {
    SGModRow *row = SGPageRow(SGL(@"settings.lyrics.pip.font", @"Font"), ^UIViewController *{
        NSMutableArray *rows = [NSMutableArray array];
        for (NSString *identifier in SGLyricsPiPFontChoices()) {
            SGModRow *choice = SGStatActionRow(SGLyricsPiPFontName(identifier), nil, nil, ^{
                [NSUserDefaults.standardUserDefaults setObject:identifier forKey:SGKeyPiPFont];
            });
            choice.checked = ^BOOL {
                return [[NSUserDefaults.standardUserDefaults stringForKey:SGKeyPiPFont] ?: @"app" isEqual:identifier];
            };
            [rows addObject:choice];
        }
        return [[SGModPage alloc] initWithTitle:SGL(@"settings.lyrics.pip.font", @"Font") intro:nil
            sections:@[SGSection(nil, rows)]
            footer:SGL(@"settings.lyrics.pip.font.note", @"Uses installed fonts, including your imported and downloaded families. Add fonts in Appearance → Font. Unavailable fonts fall back to the system font. This does not change the app font.")];
    });
    row.value = ^NSString *{
        return SGLyricsPiPFontName([NSUserDefaults.standardUserDefaults stringForKey:SGKeyPiPFont] ?: @"app");
    };
    return row;
}
static SGModRow *roleRow(NSUInteger role, NSString *title) {
    return SGPageRow(title, ^UIViewController *{
        SGModRow *size = SGSliderRow(SGL(@"settings.lyrics.pip.size", @"Size"), nil,
            role == 0 ? 24 : 16, role == 0 ? 64 : 48, 1,
            ^double { return SGLyricsPiPReadStyle().sizes[role].doubleValue; },
            ^(double value) { [NSUserDefaults.standardUserDefaults setDouble:value forKey:SGLyricsPiPRoleKey(role, @"size")]; },
            ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f", value]; });
        SGModRow *weight = SGChoiceRow(SGL(@"settings.lyrics.pip.weight", @"Weight"), nil,
            SGLyricsPiPRoleKey(role, @"weight"), weights(), role == 0 ? 2 : 0);
        return [[SGModPage alloc] initWithTitle:title intro:nil sections:@[SGSection(nil, @[size, weight])]
            footer:SGL(@"settings.lyrics.pip.fit.note", @"Sizes are maximums in the rendered frame. Long text wraps and shrinks to fit; an ellipsis marks text that still cannot fit.")];
    });
}

SGModRow *SGLyricsPiPRow(void) {
    SGModRow *row = SGPageRow(SGL(@"settings.lyrics.pip.title", @"Picture in Picture lyrics"), ^UIViewController *{
        SGModRow *enabled = SGOptionRow(SGL(@"settings.lyrics.pip.title", @"Picture in Picture lyrics"),
            SGL(@"settings.lyrics.pip.subtitle", @"Show lyrics over other apps from the lyrics screen. Restart Spotify after changing this."),
            SGKeyLyricsPiP);
        SGModRow *aspect = SGChoiceRow(SGL(@"settings.lyrics.pip.aspect", @"Aspect ratio"), nil, SGKeyPiPLayout,
            @[SGL(@"settings.lyrics.pip.square", @"Square"), SGL(@"settings.lyrics.pip.landscape", @"Landscape"),
              SGL(@"settings.lyrics.pip.portrait", @"Portrait")], 0);
        SGModRow *info = SGOptionRow(SGL(@"settings.lyrics.pip.info", @"Cover and song info"), nil, SGKeyPiPInfo);
        info.defaultOn = YES;
        SGModRow *alignment = SGChoiceRow(SGL(@"settings.lyrics.pip.alignment", @"Text alignment"), nil, SGKeyPiPAlignment,
            @[SGL(@"settings.lyrics.pip.left", @"Left"), SGL(@"settings.lyrics.pip.center", @"Center"),
              SGL(@"settings.lyrics.pip.right", @"Right")], 1);
        SGModRow *reset = SGStatActionRow(SGL(@"settings.lyrics.pip.reset", @"Reset layout and text"),
            SGL(@"settings.lyrics.pip.reset.note", @"Background and the enable switch are kept."), nil, ^{ SGLyricsPiPResetStyle(); });
        return [[SGLyricsPiPSettingsPage alloc] initWithTitle:SGL(@"settings.lyrics.pip.title", @"Picture in Picture lyrics")
            intro:SGL(@"settings.lyrics.pip.live", @"Layout, text and background apply live, even while paused. Only the enable switch requires restarting Spotify.")
            sections:@[SGSection(nil, @[enabled]),
                SGSection(SGL(@"settings.lyrics.pip.layout", @"Layout"), @[aspect, info]),
                SGSection(SGL(@"settings.lyrics.pip.text", @"Text"), @[alignment, fontRow(),
                    roleRow(0, SGL(@"settings.lyrics.pip.original", @"Original")),
                    roleRow(1, SGL(@"settings.lyrics.pip.pronunciation", @"Pronunciation")),
                    roleRow(2, SGL(@"settings.lyrics.pip.translation", @"Translation")), reset]),
                SGSection(SGL(@"settings.lyrics.pip.background", @"Background"), SGLyricsBackgroundRows(SGKeyLyricsPiPBackground))]
            footer:SGL(@"settings.lyrics.pip.extras.note", @"Shows available pronunciation and translation using your lyrics display and language rules. Opening Picture in Picture never starts translation or AI.")];
    });
    row.subtitle = SGL(@"settings.lyrics.pip.page.subtitle", @"Open lyrics over other apps and customize their background.");
    return row;
}
