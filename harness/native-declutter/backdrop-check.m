// The production installer with view/image doubles; Core's renderer is not under test here.
#import "Native/Appearance/HeaderBackdrop.h"

@implementation UIImage
// Equal-valued but distinct images must still refresh the sampled image.
- (BOOL)isEqual:(id)other { return [other isKindOfClass:UIImage.class]; }
- (NSUInteger)hash { return 1; }
@end
@implementation UIImageView
@end

@interface HeaderBackdrop : UIView
@property (nonatomic) CGFloat bottomAlpha;
@end
@implementation HeaderBackdrop
@end

UIView *SGBackdropMake(CGRect frame, CGFloat bottomAlpha) {
    HeaderBackdrop *backdrop = [HeaderBackdrop new];
    backdrop.bounds = frame;
    backdrop.bottomAlpha = bottomAlpha;
    [backdrop insertSubview:[UIImageView new] atIndex:0];
    return backdrop;
}
UIImageView *SGBackdropImageView(UIView *backdrop) { return (UIImageView *)backdrop.subviews.firstObject; }
UIImage *SGBackdropSample(UIImage *image) { return [UIImage new]; }

static NSUInteger checks;
static void check(BOOL ok, NSString *name) {
    if (!ok) {
        NSLog(@"FAIL native header backdrop: %@", name);
        exit(1);
    }
    checks++;
}

static UIView *header(void) {
    UIView *view = [UIView new];
    view.bounds = CGRectMake(0, 0, 320, 240);
    [view insertSubview:[UIView new] atIndex:0];
    [view insertSubview:[UIView new] atIndex:1];
    return view;
}

int main(void) {
    @autoreleasepool {
        static char albumBackdrop, albumSource, playlistBackdrop, playlistSource;
        UIView *host = header(), *wash = host.subviews[0], *shade = host.subviews[1];
        UIImage *source = [UIImage new];
        SGNativeHeaderBackdrop(host, source, &albumBackdrop, &albumSource);
        HeaderBackdrop *backdrop = (HeaderBackdrop *)host.subviews[1];
        check([host.subviews isEqual:@[wash, backdrop, shade]], @"backdrop goes between existing header layers");
        check(CGRectEqualToRect(backdrop.bounds, CGRectMake(0, 0, 320, 240)) && backdrop.bottomAlpha == 1,
              @"new backdrop uses header bounds and opaque bottom");
        UIImage *sample = SGBackdropImageView(backdrop).image;
        check(sample != nil, @"first artwork is published synchronously");
        SGNativeHeaderBackdrop(host, source, &albumBackdrop, &albumSource);
        check(host.subviews.count == 3 && SGBackdropImageView(backdrop).image == sample,
              @"same image retains the installed backdrop and sample");
        source = [UIImage new];
        SGNativeHeaderBackdrop(host, source, &albumBackdrop, &albumSource);
        check(SGBackdropImageView(backdrop).image != sample, @"equal-valued new image refreshes the sample");
        sample = SGBackdropImageView(backdrop).image;
        [backdrop removeFromSuperview];
        SGNativeHeaderBackdrop(host, source, &albumBackdrop, &albumSource);
        check(host.subviews[1] == backdrop && SGBackdropImageView(backdrop).image == sample,
              @"detached backdrop is reinserted even when the source is unchanged");
        SGNativeHeaderBackdrop(host, source, &playlistBackdrop, &playlistSource);
        check(host.subviews.count == 4 && host.subviews[1] != backdrop && host.subviews[2] == backdrop,
              @"caller association keys keep their backdrops separate");
        UIView *other = header();
        SGNativeHeaderBackdrop(other, source, &albumBackdrop, &albumSource);
        check(other.subviews[1] != backdrop && backdrop.superview == host, @"different headers own independent backdrops");
        NSLog(@"PASS native header backdrop: %lu checks", (unsigned long)checks);
    }
    return 0;
}
