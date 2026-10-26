#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "AppIcon.h"

static id ofClass(id value, Class kind) {
    return [value isKindOfClass:kind] ? value : nil;
}

static NSDictionary *alternateIcons(void) {
    NSDictionary *icons = ofClass([NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleIcons"], NSDictionary.class);
    return ofClass(icons[@"CFBundleAlternateIcons"], NSDictionary.class);
}

// The names Info.plist declares, sorted, so the list reads the same each time.
static NSArray<NSString *> *iconNames(void) {
    return [alternateIcons().allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)] ?: @[];
}

static NSString *label(NSString *name) {
    return name ? [name stringByReplacingOccurrencesOfString:@"_" withString:@" "] : SGL(@"settings.appicon.choice.default", @"Default");
}

// The image an icon is drawn from, the last of its CFBundleIconFiles: scripts/pipeline.sh puts an alternate's
// <name>@2x.png and @3x.png at the bundle's root under its own name, and the primary icon's names are Spotify's.
static UIImage *iconImage(NSString *icon) {
    NSDictionary *icons = ofClass([NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleIcons"], NSDictionary.class);
    NSDictionary *entry = ofClass(icon ? alternateIcons()[icon] : icons[@"CFBundlePrimaryIcon"], NSDictionary.class);
    NSArray *files = ofClass(entry[@"CFBundleIconFiles"], NSArray.class);
    NSString *file = ofClass(files.lastObject, NSString.class) ?: icon;
    return file ? [UIImage imageNamed:file] : nil;
}

static const CGFloat kThumb = 60;

// The icon at 60pt in the home screen's rounded square, edged with a hairline so a dark icon still shows on the
// card; a gray square where the image is not found.
static UIImage *thumbnail(NSString *icon) {
    UIImage *art = iconImage(icon);
    CGRect box = CGRectMake(0, 0, kThumb, kThumb);
    UIImage *drawn = [[[UIGraphicsImageRenderer alloc] initWithSize:box.size] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        // UIBezierPath's rounded rectangle has the continuous corner of the home screen's icons.
        UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:box cornerRadius:kThumb * 0.225];
        [shape addClip];
        if (art) [art drawInRect:box];
        else {
            [[UIColor colorWithWhite:0.23 alpha:1] setFill];
            [shape fill];
        }
        [[UIColor colorWithWhite:1 alpha:0.18] setStroke];
        shape.lineWidth = 2 / UIScreen.mainScreen.scale;   // half of it inside the clip
        [shape stroke];
    }];
    return [drawn imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

static BOOL isCurrent(NSString *icon) {
    NSString *current = UIApplication.sharedApplication.alternateIconName;
    return current == icon || [current isEqualToString:icon];
}

static void setIcon(NSString *icon, void (^done)(void)) {
    [UIApplication.sharedApplication setAlternateIconName:icon completionHandler:^(NSError *error) {
        if (!error) {
            // iOS says so itself when it worked; the handler can run off the main thread.
            if (done) dispatch_async(dispatch_get_main_queue(), done);
            return;
        }
        SGLog(@"app icon: %@ not set: %@", label(icon), error.localizedDescription);
        // A re-signed install, or a call while the app is not frontmost, can be refused; without
        // a word the row looks broken. The handler can run off the main thread.
        dispatch_async(dispatch_get_main_queue(), ^{
            SGPresentInformation(SGTopController(), SGL(@"settings.appicon.error.alert.title", @"The icon did not change"), error.localizedDescription);
        });
    }];
}

// Default and then each icon, as a picture beside its name, a checkmark against the one on the home screen. A
// pick stays on the page, and the checkmark moves once iOS has taken it.
@interface SGAppIconPage : SGPage
- (instancetype)initWithNames:(NSArray<NSString *> *)names;
@end

@implementation SGAppIconPage {
    NSArray<NSString *> *_names;
}

- (instancetype)initWithNames:(NSArray<NSString *> *)names {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = SGL(@"settings.appicon.title", @"App icon");
    _names = names;
    return self;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (NSString *)iconAt:(NSIndexPath *)path {
    return path.row > 0 ? _names[(NSUInteger)path.row - 1] : nil;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_names.count + 1;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    NSString *icon = [self iconAt:path];
    UITableViewCell *cell = SGDequeueCell(table, @"icon");
    SGFillCell(cell, label(icon), nil, nil, nil);
    UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
    content.image = thumbnail(icon);
    content.imageProperties.maximumSize = CGSizeMake(kThumb, kThumb);
    content.imageProperties.reservedLayoutSize = CGSizeMake(kThumb, kThumb);
    content.imageToTextPadding = 14;
    content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(10, 16, 10, 16);
    cell.contentConfiguration = content;
    cell.separatorInset = UIEdgeInsetsMake(0, 16 + kThumb + 14, 0, 0);
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    BOOL current = isCurrent(icon);
    // SGChoicePage's checkmark.
    UIImageView *tick = current ? SGSymbolView(@"checkmark", 13, UIImageSymbolWeightSemibold, 16) : nil;
    tick.tintColor = SGGreen();
    cell.accessoryView = tick;
    cell.accessibilityTraits = UIAccessibilityTraitButton | (current ? UIAccessibilityTraitSelected : 0);
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    NSString *icon = [self iconAt:path];
    if (isCurrent(icon)) return;
    __weak UITableView *weakTable = table;
    setIcon(icon, ^{ [weakTable reloadData]; });
}

@end

// A page of the icons as pictures, the current one's name beside the chevron.
SGModRow *SGAppIconRow(void) {
    NSArray<NSString *> *names = iconNames();
    if (!names.count || !UIApplication.sharedApplication.supportsAlternateIcons) return nil;
    SGModRow *row = SGPageRow(SGL(@"settings.appicon.title", @"App icon"), ^UIViewController *{ return [[SGAppIconPage alloc] initWithNames:names]; });
    row.value = ^NSString *{ return label(UIApplication.sharedApplication.alternateIconName); };
    return SGWithSymbol(row, @"app.badge");
}
