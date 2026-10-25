// Production field and flow layers, with palette completions delivered in a chosen order.
#import <UIKit/UIKit.h>
#import "Redesigned/Kit/SGRField.h"
#import "Redesigned/Kit/SGRFlow.h"
#import "Redesigned/Kit/SGRFluid.h"
#import "Redesigned/Kit/SGRPalette.h"

UIColor *SGRAccentColor(void) { return UIColor.greenColor; }
BOOL SGRPlayerIsTransitioning(void) { return NO; }
void SGRObservePlayerTransition(id owner, void (^began)(id), void (^ended)(id)) {}
UIColor *SGRFieldColorFor(UIColor *color) { return color; }

// Fluid is not selected by these checks.
@implementation SGRFluidLayer
- (void)setArtwork:(UIImage *)image animated:(BOOL)animated {
    fprintf(stderr, "FAIL unexpected fluid artwork request\n");
    exit(1);
}
@end

@interface SGRPalette ()
@property (nonatomic, readwrite) UIColor *fieldColor;
@property (nonatomic, readwrite) NSArray<UIColor *> *flowColors;
@end

static NSMutableArray<void (^)(void)> *pending;

@implementation SGRPalette
+ (void)paletteForImage:(UIImage *)image request:(SGRPaletteRequest)request completion:(void (^)(SGRPalette *))completion {
    SGRPalette *palette = [SGRPalette new];
    palette.fieldColor = request.flow ? UIColor.cyanColor : UIColor.redColor;
    if (request.flow) palette.flowColors = @[UIColor.blueColor, UIColor.blueColor, UIColor.blueColor,
                                           UIColor.blueColor, UIColor.blueColor];
    [pending addObject:^{ completion(palette); }];
}
+ (void)tintForImage:(UIImage *)image surface:(UIColor *)surface strong:(BOOL)strong completion:(void (^)(UIColor *))completion {
    fprintf(stderr, "FAIL unexpected tint request\n");
    exit(1);
}
@end

static NSArray *takeReplies(void) {
    NSArray *replies = [pending copy];
    [pending removeAllObjects];
    return replies;
}

static void deliver(NSArray *replies) {
    for (void (^reply)(void) in replies) reply();
}

static BOOL showsFlow(SGRArtworkField *field) {
    for (CALayer *layer in field.layer.sublayers) {
        if ([layer isKindOfClass:SGRFlowLayer.class] && !layer.hidden &&
            ((SGRFlowLayer *)layer).baseColor != nil) return YES;
    }
    return NO;
}

static int failures;
static void check(BOOL passed, const char *description) {
    printf("%s %s\n", passed ? "PASS" : "FAIL", description);
    if (!passed) failures++;
}

int main(void) {
    @autoreleasepool {
        pending = [NSMutableArray array];
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(8, 8)];
        UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [UIColor.blueColor setFill];
            UIRectFill(CGRectMake(0, 0, 8, 8));
        }];
        SGRArtworkField *field = [[SGRArtworkField alloc] initWithFrame:CGRectMake(0, 0, 300, 500)];
        [field setArtwork:image identity:@"cover" animated:NO];
        NSArray *oldStill = takeReplies();
        field.flows = YES;
        deliver(takeReplies());
        check(showsFlow(field), "artwork supplied before Colours configuration becomes a visible flow");
        deliver(oldStill);
        check(showsFlow(field) && ![field.fieldColor isEqual:UIColor.redColor],
              "a late still-mode palette cannot overwrite the Colours field");

        // A completed palette must not make the same artwork permanently ineligible for another mode.
        field.flows = NO;
        deliver(takeReplies());
        field.flows = YES;
        [field setArtwork:image identity:@"cover" animated:NO];
        deliver(takeReplies());
        check(showsFlow(field), "retained artwork restores Colours after a completed mode change");

        SGRArtworkField *returning = [[SGRArtworkField alloc] initWithFrame:CGRectMake(0, 0, 300, 500)];
        returning.flows = YES;
        [returning setArtwork:image identity:@"cover" animated:NO];
        NSArray *oldFlow = takeReplies();
        returning.flows = NO;
        deliver(takeReplies());
        deliver(oldFlow);
        check(!showsFlow(returning) && [returning.fieldColor isEqual:UIColor.redColor],
              "leaving Colours retires its pending palette and applies the still-mode palette");
        printf("%d failed\n", failures);
        return failures ? 1 : 0;
    }
}
