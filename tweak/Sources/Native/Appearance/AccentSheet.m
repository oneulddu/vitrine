// The native look's accent color sheet (SGPickAccent, Appearance.h): the colors chosen before as a row of swatches
// over the system color picker, which sits in the sheet as its child. The redesign has its own copy
// (Redesigned/Kit/SGRAccentSheet.m).
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Appearance.h"

// A swatch's disc, and the ring that stands off the current one; each swatch is a 44pt touch target.
static const CGFloat kSwatchDiameter = 28, kRingWidth = 2, kRingGap = 2, kSwatchTarget = 44;
// A dark edge around the disc and on both sides of the ring, so a white or very light swatch and the white ring
// still show their edges.
static const CGFloat kOutlineWidth = 0.75, kOutlineAlpha = 0.25;
// The swatches' row from the sheet's sides, and its caption from the top.
static const CGFloat kStripInset = 10, kCaptionTop = 12;

static NSString *hexOf(NSInteger rgb) {
    return [NSString stringWithFormat:@"#%06lX", (long)rgb];
}

// The disc is drawn into an image, past the accent hooks on layer backgrounds (see SGColorRGB).
// From the image's edge in: the outline, the ring, the gap, the disc.
static UIImage *swatchImage(NSInteger rgb, BOOL current) {
    CGFloat side = kSwatchDiameter + 2 * (kRingWidth + kRingGap + kOutlineWidth);
    CGRect bounds = CGRectMake(0, 0, side, side);
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:bounds.size] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextRef cg = context.CGContext;
        CGColorRef outline = [UIColor colorWithWhite:0 alpha:kOutlineAlpha].CGColor;
        CGContextSetLineWidth(cg, kOutlineWidth);
        CGRect disc = CGRectInset(bounds, kOutlineWidth + kRingWidth + kRingGap, kOutlineWidth + kRingWidth + kRingGap);
        CGContextSetFillColorWithColor(cg, SGColorRGB(rgb).CGColor);
        CGContextFillEllipseInRect(cg, disc);
        // A light hairline just inside, so a color as dark as the sheet still shows, and the dark edge just outside.
        CGContextSetStrokeColorWithColor(cg, [UIColor colorWithWhite:1 alpha:0.3].CGColor);
        CGContextStrokeEllipseInRect(cg, CGRectInset(disc, kOutlineWidth / 2, kOutlineWidth / 2));
        CGContextSetStrokeColorWithColor(cg, outline);
        CGContextStrokeEllipseInRect(cg, CGRectInset(disc, -kOutlineWidth / 2, -kOutlineWidth / 2));
        if (!current) return;
        CGContextSetStrokeColorWithColor(cg, UIColor.whiteColor.CGColor);
        CGContextSetLineWidth(cg, kRingWidth);
        CGContextStrokeEllipseInRect(cg, CGRectInset(bounds, kOutlineWidth + kRingWidth / 2, kOutlineWidth + kRingWidth / 2));
        CGContextSetStrokeColorWithColor(cg, outline);
        CGContextSetLineWidth(cg, kOutlineWidth);
        CGContextStrokeEllipseInRect(cg, CGRectInset(bounds, kOutlineWidth / 2, kOutlineWidth / 2));
        CGContextStrokeEllipseInRect(cg, CGRectInset(bounds, kOutlineWidth * 1.5 + kRingWidth, kOutlineWidth * 1.5 + kRingWidth));
    }];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

@interface SGAccentSheet : UIViewController
@end

@implementation SGAccentSheet {
    NSInteger _current;
    NSArray<NSNumber *> *_recent;
    void (^_chosen)(NSInteger rgb);
    UIColorPickerViewController *_picker;
}

- (instancetype)initWithCurrent:(NSInteger)current recent:(NSArray<NSNumber *> *)recent chosen:(void (^)(NSInteger rgb))chosen {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    _current = current;
    _recent = [recent copy];
    _chosen = [chosen copy];
    return self;
}

- (UIButton *)swatchFor:(NSInteger)rgb {
    BOOL current = rgb == _current;
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setImage:swatchImage(rgb, current) forState:UIControlStateNormal];
    button.tag = rgb;
    [button addTarget:self action:@selector(swatchTapped:) forControlEvents:UIControlEventTouchUpInside];
    NSString *name = SGColorRGB(rgb).accessibilityName;
    button.accessibilityLabel = name.length ? name : hexOf(rgb);
    button.accessibilityValue = name.length ? hexOf(rgb) : nil;
    button.accessibilityTraits = UIAccessibilityTraitButton | (current ? UIAccessibilityTraitSelected : 0);
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:kSwatchTarget],
        [button.heightAnchor constraintEqualToConstant:kSwatchTarget],
    ]];
    return button;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *view = self.view;
    view.backgroundColor = UIColor.systemBackgroundColor;
    _picker = [UIColorPickerViewController new];
    _picker.supportsAlpha = NO;
    _picker.selectedColor = SGColorRGB(_current);
    [self addChildViewController:_picker];
    UIView *pickerView = _picker.view;
    pickerView.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:pickerView];

    NSLayoutYAxisAnchor *pickerTop = view.safeAreaLayoutGuide.topAnchor;
    if (_recent.count) {
        UILabel *caption = [UILabel new];
        caption.text = SGL(@"settings.appearance.accent_recent.header", @"Recent colors");
        caption.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        caption.adjustsFontForContentSizeCategory = YES;
        caption.textColor = UIColor.secondaryLabelColor;
        caption.accessibilityTraits = UIAccessibilityTraitHeader;
        caption.translatesAutoresizingMaskIntoConstraints = NO;
        [view addSubview:caption];

        UIStackView *swatches = [UIStackView new];
        swatches.axis = UILayoutConstraintAxisHorizontal;
        for (NSNumber *rgb in _recent) [swatches addArrangedSubview:[self swatchFor:rgb.integerValue]];
        swatches.translatesAutoresizingMaskIntoConstraints = NO;
        // Eight fit across a 375pt iPhone; a narrower sheet scrolls them.
        UIScrollView *strip = [UIScrollView new];
        strip.showsHorizontalScrollIndicator = NO;
        strip.translatesAutoresizingMaskIntoConstraints = NO;
        [strip addSubview:swatches];
        [view addSubview:strip];
        // The caption starts where the first swatch shows: the dark edge outside its disc, or outside the ring around
        // it when it is the current one.
        CGFloat captionInset = kStripInset + (kSwatchTarget - kSwatchDiameter) / 2 - kOutlineWidth
            - (_recent.firstObject.integerValue == _current ? kRingWidth + kRingGap : 0);
        [NSLayoutConstraint activateConstraints:@[
            [caption.topAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.topAnchor constant:kCaptionTop],
            [caption.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:captionInset],
            [caption.trailingAnchor constraintLessThanOrEqualToAnchor:view.trailingAnchor constant:-kStripInset],
            [strip.topAnchor constraintEqualToAnchor:caption.bottomAnchor],
            [strip.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:kStripInset],
            [strip.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-kStripInset],
            [strip.heightAnchor constraintEqualToConstant:kSwatchTarget],
            [swatches.topAnchor constraintEqualToAnchor:strip.contentLayoutGuide.topAnchor],
            [swatches.bottomAnchor constraintEqualToAnchor:strip.contentLayoutGuide.bottomAnchor],
            [swatches.leadingAnchor constraintEqualToAnchor:strip.contentLayoutGuide.leadingAnchor],
            [swatches.trailingAnchor constraintEqualToAnchor:strip.contentLayoutGuide.trailingAnchor],
            [swatches.heightAnchor constraintEqualToAnchor:strip.frameLayoutGuide.heightAnchor],
        ]];
        pickerTop = strip.bottomAnchor;
    }
    [NSLayoutConstraint activateConstraints:@[
        [pickerView.topAnchor constraintEqualToAnchor:pickerTop],
        [pickerView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [pickerView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [pickerView.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
    ]];
    [_picker didMoveToParentViewController:self];
}

- (void)choose:(NSInteger)rgb {
    void (^chosen)(NSInteger rgb) = _chosen;
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    chosen(rgb);
}

- (void)swatchTapped:(UIButton *)button {
    [self choose:button.tag];
}

- (void)confirm {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [_picker.selectedColor getRed:&r green:&g blue:&b alpha:&a];
    [self choose:(lround(MIN(1, MAX(0, r)) * 255) << 16) | (lround(MIN(1, MAX(0, g)) * 255) << 8) | lround(MIN(1, MAX(0, b)) * 255)];
}

- (void)cancel {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

@end

void SGPickAccent(NSString *title, NSInteger current, NSArray<NSNumber *> *recent, void (^chosen)(NSInteger rgb)) {
    SGAccentSheet *sheet = [[SGAccentSheet alloc] initWithCurrent:current recent:recent chosen:chosen];
    sheet.navigationItem.title = title;
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"checkmark"] style:UIBarButtonItemStyleDone target:sheet action:@selector(confirm)];
    done.accessibilityLabel = SGL(@"common.done", @"Done");
    sheet.navigationItem.rightBarButtonItem = done;
    sheet.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:sheet action:@selector(cancel)];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:sheet];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    SGPresentDark(nav);
    [SGTopController() presentViewController:nav animated:YES completion:nil];
}
