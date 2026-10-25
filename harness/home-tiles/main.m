// Real tile styling and image observation; palette work and Home preferences are test doubles.
#import <UIKit/UIKit.h>
#import "Redesigned/Home/Home.h"
#import "Redesigned/Kit/SGRPalette.h"
#import "../harness-fail.h"

BOOL SGRHomeLook(void) { return YES; }
CFTimeInterval SGRHomeProbeBegin(void) { return 0; }
void SGRHomeProbeEnd(SGRHomeProbe probe, CFTimeInterval began) {}
UIColor *SGRAccentColor(void) { return nil; }

@implementation SGRPalette
+ (void)tintForImage:(UIImage *)image surface:(UIColor *)surface strong:(BOOL)strong completion:(void (^)(UIColor *))completion {
    completion(nil);
}
@end

static void checkReuse(BOOL measured) {
    UIView *tile = [[UIView alloc] initWithFrame:CGRectMake(0, 0, measured ? 181 : 0, 48)];
    tile.accessibilityIdentifier = @"Shortcut.Card.Home";
    UIView *fill = [[UIView alloc] initWithFrame:tile.bounds];
    [tile addSubview:fill];
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 181, 48)];
    [tile addSubview:row];
    UIView *square = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 48, 48)];
    [row addSubview:square];
    UIView *holder = [[UIView alloc] initWithFrame:square.bounds];
    holder.accessibilityIdentifier = @"Encore.ImageView";
    [square addSubview:holder];
    UIImageView *cover = [[UIImageView alloc] initWithFrame:holder.bounds];
    [holder addSubview:cover];
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(56, 0, 100, 48)];
    title.accessibilityIdentifier = @"Shortcut.Card.Home.Content.title-internal";
    title.text = @"Shortcut";
    [row addSubview:title];

    SGRHomeStyleTile(tile);
    if (measured) HARNESS_CHECK(!CGAffineTransformIsIdentity(square.transform));
    tile.accessibilityIdentifier = @"Components.UI.HomeCard";
    SGRHomeUnstyleTile(tile);
    tile.bounds = CGRectMake(0, 0, 181, 48);
    fill.frame = tile.bounds;
    cover.image = [UIImage systemImageNamed:@"music.note"];
    HARNESS_CHECK(tile.subviews.count == 2);
    HARNESS_CHECK(CGAffineTransformIsIdentity(square.transform));
    HARNESS_CHECK(CGAffineTransformIsIdentity(title.transform));
    HARNESS_CHECK(title.alpha == 1);
    NSLog(@"[harness] PASS image update leaves %@ reused card unstyled", measured ? @"measured" : @"not-yet-measured");

    tile.accessibilityIdentifier = @"Shortcut.Card.Home";
    SGRHomeStyleTile(tile);
    HARNESS_CHECK(!CGAffineTransformIsIdentity(square.transform));
    NSLog(@"[harness] PASS reused card can become a shortcut again");
}

@interface HomeTilesController : UIViewController
@end
@implementation HomeTilesController
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    checkReuse(YES);
    checkReuse(NO);
    NSLog(@"[harness] done");
    exit(0);
}
@end

@interface HomeTilesDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation HomeTilesDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [HomeTilesController new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(HomeTilesDelegate.class));
    }
}
