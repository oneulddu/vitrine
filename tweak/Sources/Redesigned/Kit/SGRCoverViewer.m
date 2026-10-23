// The Kit's full screen cover (SGRCoverViewer.h). Black, the cover fitted to the screen, pinched or double tapped
// to zoom, and dragged down or closed to go; Share hands the picture to the system's share sheet, which saves it to
// Photos too.
//
// The picture is the one the page's header shows -- on an album the still cover even while Apple Music's animated
// one plays over it: the largest Spotify has fetched for the page, as no larger size of its image addresses is
// known here.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "SGRKit.h"
#import "SGRCoverViewer.h"

// How far down a drag has to take the cover, or how fast, for it to go; and as far as it zooms.
static const CGFloat kDismissDistance = 120, kDismissVelocity = 900, kMaxZoom = 4, kDoubleTapZoom = 2.5;
static const CGFloat kButton = 44;

@interface SGRCoverViewer : UIViewController <UIScrollViewDelegate, UIGestureRecognizerDelegate>
- (instancetype)initWithImage:(UIImage *)image name:(NSString *)name;
@end

@implementation SGRCoverViewer {
    UIImage *_image;
    NSString *_name;
    UIScrollView *_scroll;
    UIImageView *_picture;
    UIButton *_close, *_share;
    UIPanGestureRecognizer *_drag;
    BOOL _chromeHidden;
}

- (instancetype)initWithImage:(UIImage *)image name:(NSString *)name {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    _image = image;
    _name = [name copy];
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    self.modalPresentationCapturesStatusBarAppearance = YES;
    return self;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (BOOL)prefersStatusBarHidden {
    return _chromeHidden;
}

- (UIButton *)buttonWithSymbol:(NSString *)symbol label:(NSString *)label action:(SEL)action {
    UIButtonConfiguration *config;
    if (@available(iOS 26.0, *)) config = [UIButtonConfiguration glassButtonConfiguration];
    else config = [UIButtonConfiguration grayButtonConfiguration];
    config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    config.baseForegroundColor = UIColor.whiteColor;
    config.image = [UIImage systemImageNamed:symbol];
    config.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];
    config.contentInsets = NSDirectionalEdgeInsetsZero;
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
    [button addTarget:self action:action forControlEvents:UIControlEventPrimaryActionTriggered];
    button.accessibilityLabel = label;
    button.pointerInteractionEnabled = YES;
    [self.view addSubview:button];
    return button;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    _scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scroll.delegate = self;
    _scroll.minimumZoomScale = 1;
    _scroll.maximumZoomScale = kMaxZoom;
    _scroll.showsHorizontalScrollIndicator = NO;
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _scroll.decelerationRate = UIScrollViewDecelerationRateFast;
    [self.view addSubview:_scroll];

    _picture = [[UIImageView alloc] initWithImage:_image];
    _picture.contentMode = UIViewContentModeScaleAspectFit;
    _picture.isAccessibilityElement = YES;
    _picture.accessibilityTraits = UIAccessibilityTraitImage;
    _picture.accessibilityLabel = _name;
    [_scroll addSubview:_picture];

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(sgr_doubleTapped:)];
    doubleTap.numberOfTapsRequired = 2;
    [_scroll addGestureRecognizer:doubleTap];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(sgr_tapped)];
    [tap requireGestureRecognizerToFail:doubleTap];
    [_scroll addGestureRecognizer:tap];
    _drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(sgr_dragged:)];
    _drag.maximumNumberOfTouches = 1;
    _drag.delegate = self;
    [self.view addGestureRecognizer:_drag];

    _close = [self buttonWithSymbol:@"xmark" label:SGL(@"settings.cover_viewer.close", @"Close") action:@selector(sgr_close)];
    _share = [self buttonWithSymbol:@"square.and.arrow.up" label:SGL(@"settings.cover_viewer.share", @"Share")
                             action:@selector(sgr_share)];
    self.view.accessibilityElements = @[_close, _picture, _share];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGFloat top = MAX(safe.top, 20) + 8;
    BOOL rtl = self.view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGRect leading = CGRectMake(SGRSideMargin + safe.left, top, kButton, kButton);
    CGRect trailing = CGRectMake(bounds.size.width - SGRSideMargin - safe.right - kButton, top, kButton, kButton);
    _close.frame = rtl ? trailing : leading;
    _share.frame = rtl ? leading : trailing;
    // At rest the picture fits the screen; a zoom in progress keeps the size it has.
    if (_scroll.zoomScale <= _scroll.minimumZoomScale && _image.size.width > 0 && _image.size.height > 0) {
        CGFloat fit = MIN(bounds.size.width / _image.size.width, bounds.size.height / _image.size.height);
        CGSize size = CGSizeMake(floor(_image.size.width * fit), floor(_image.size.height * fit));
        if (!CGSizeEqualToSize(_picture.frame.size, size)) {
            _picture.frame = CGRectMake(0, 0, size.width, size.height);
            _scroll.contentSize = size;
        }
    }
    [self sgr_centre];
}

// The picture in the middle of the screen while it is smaller than the screen.
- (void)sgr_centre {
    CGSize bounds = _scroll.bounds.size, content = _scroll.contentSize;
    CGFloat x = MAX(0, (bounds.width - content.width) / 2), y = MAX(0, (bounds.height - content.height) / 2);
    UIEdgeInsets inset = UIEdgeInsetsMake(y, x, y, x);
    if (!UIEdgeInsetsEqualToEdgeInsets(_scroll.contentInset, inset)) _scroll.contentInset = inset;
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return _picture;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    [self sgr_centre];
}

- (void)sgr_doubleTapped:(UITapGestureRecognizer *)tap {
    if (_scroll.zoomScale > _scroll.minimumZoomScale + 0.01) {
        [_scroll setZoomScale:_scroll.minimumZoomScale animated:YES];
        return;
    }
    CGPoint point = [tap locationInView:_picture];
    CGSize size = CGSizeMake(_scroll.bounds.size.width / kDoubleTapZoom, _scroll.bounds.size.height / kDoubleTapZoom);
    [_scroll zoomToRect:CGRectMake(point.x - size.width / 2, point.y - size.height / 2, size.width, size.height) animated:YES];
}

// A tap shows or hides the two buttons and the status bar, as Photos does.
- (void)sgr_tapped {
    _chromeHidden = !_chromeHidden;
    CGFloat alpha = _chromeHidden ? 0 : 1;
    [UIView animateWithDuration:0.2 animations:^{
        self->_close.alpha = alpha;
        self->_share.alpha = alpha;
        [self setNeedsStatusBarAppearanceUpdate];
    }];
    _close.accessibilityElementsHidden = _share.accessibilityElementsHidden = _chromeHidden;
}

// A drag only takes over at rest and only going down; zoomed in, the scroll view's own pan moves the picture.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (gesture != _drag) return YES;
    if (_scroll.zoomScale > _scroll.minimumZoomScale + 0.01) return NO;
    CGPoint velocity = [_drag velocityInView:self.view];
    return velocity.y > 0 && fabs(velocity.y) > fabs(velocity.x);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return gesture == _drag && other == _scroll.panGestureRecognizer;
}

- (void)sgr_dragged:(UIPanGestureRecognizer *)drag {
    CGPoint moved = [drag translationInView:self.view];
    CGFloat down = MAX(0, moved.y);
    CGFloat progress = MIN(1, down / (self.view.bounds.size.height / 2));
    switch (drag.state) {
        case UIGestureRecognizerStateChanged: {
            CGFloat scale = 1 - 0.2 * progress;
            _scroll.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(moved.x * 0.5, down), scale, scale);
            self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:1 - progress];
            CGFloat chrome = _chromeHidden ? 0 : 1 - MIN(1, progress * 3);
            _close.alpha = _share.alpha = chrome;
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            CGFloat velocity = [drag velocityInView:self.view].y;
            if (drag.state == UIGestureRecognizerStateEnded && (down > kDismissDistance || velocity > kDismissVelocity)) {
                [self sgr_dismissFalling];
                return;
            }
            CGFloat chrome = _chromeHidden ? 0 : 1;
            [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:1 initialSpringVelocity:0 options:0 animations:^{
                self->_scroll.transform = CGAffineTransformIdentity;
                self.view.backgroundColor = UIColor.blackColor;
                self->_close.alpha = self->_share.alpha = chrome;
            } completion:nil];
            break;
        }
        default:
            break;
    }
}

- (void)sgr_dismissFalling {
    CGFloat height = self.view.bounds.size.height;
    [UIView animateWithDuration:SGRReduceMotion() ? 0.15 : 0.25 animations:^{
        if (SGRReduceMotion()) self->_scroll.alpha = 0;
        else self->_scroll.transform = CGAffineTransformTranslate(self->_scroll.transform, 0, height);
        self.view.backgroundColor = UIColor.clearColor;
        self->_close.alpha = self->_share.alpha = 0;
    } completion:^(BOOL finished) {
        [self dismissViewControllerAnimated:NO completion:nil];
    }];
}

- (void)sgr_close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)accessibilityPerformEscape {
    [self sgr_close];
    return YES;
}

- (void)sgr_share {
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[_image] applicationActivities:nil];
    sheet.popoverPresentationController.sourceView = _share;
    sheet.popoverPresentationController.sourceRect = _share.bounds;
    SGPresentDark(sheet);
    [self presentViewController:sheet animated:YES completion:nil];
}

@end

void SGRShowCover(UIImage *image, NSString *accessibilityName) {
    if (!image) return;
    UIViewController *top = SGTopController();
    if (!top) return;
    SGRCoverViewer *viewer = [[SGRCoverViewer alloc] initWithImage:image name:accessibilityName];
    SGPresentDark(viewer);
    [top presentViewController:viewer animated:YES completion:nil];
    SGLog(@"redesign: \"%@\" full screen, %.0fx%.0f px", accessibilityName ?: @"cover", image.size.width * image.scale,
          image.size.height * image.scale);
}
