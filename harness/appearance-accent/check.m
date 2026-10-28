#import <UIKit/UIKit.h>
#import "Core/SGPrefs.h"
#import "Core/SGTopController.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "Redesigned/Kit/SGRBridges.h"
#import "Redesigned/Kit/SGRPalette.h"
#import "../harness-fail.h"

static UIViewController *front;
static UIImage *cover;
static NSString *coverTrack, *trackURI;
static id<SGPlayerStateObserver> observer;
static NSMutableArray *replies;
NSNotificationName const SGRNowPlayingArtworkDidChangeNotification = @"harness.artwork";
NSNotificationName const SGRFieldColorDidChangeNotification = @"harness.field";
// Supply a typed negative preference before the tweak constructors. Foundation's command-line
// argument domain does not supply the "-1" value in this console executable.
@interface SGRStockLaunchDefaults : NSObject @end
@implementation SGRStockLaunchDefaults
+ (void)load {
    if ([NSProcessInfo.processInfo.arguments containsObject:@"stock"]) {
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGRKeyAccent:@(-1),SGRKeyAccentAuto:@NO} forName:NSArgumentDomain];
        SGPrefsChanged();
    }
}
@end
BOOL SGRedesignedUI(void) { return YES; }
UIWindow *SGAppWindow(void) { return nil; }
UIViewController *SGTopControllerInWindow(UIWindow *window, NSMutableArray *path, NSMutableArray *presented) { return front; }
NSString *SGURIString(id uri) { return uri; }
UIImage *SGRNowPlayingArtwork(NSString **track, NSString **identity) {
    if (track) *track = coverTrack;
    if (identity) *identity = coverTrack;
    return cover;
}
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> value) { observer = value; }
// The owner's only read is state.track.URI.
@interface Track : NSObject
@property (nonatomic, copy) NSString *URI;
@end
@implementation Track @end
@interface State : NSObject
@property (nonatomic, strong) Track *track;
@end
@implementation State @end
SPTPlayerState *SGPlayerState(void) {
    State *state = [State new]; state.track = [Track new]; state.track.URI = trackURI;
    return (id)state;
}
@interface SGRPalette ()
@property (nonatomic, readwrite) UIColor *fieldColor;
@end
@implementation SGRPalette
+ (void)paletteForImage:(UIImage *)image request:(SGRPaletteRequest)request completion:(void (^)(SGRPalette *))completion {
    [replies addObject:[completion copy]];
}
+ (void)tintForImage:(UIImage *)image surface:(UIColor *)surface strong:(BOOL)strong completion:(void (^)(UIColor *))completion {
    HARNESS_FAIL(@"unexpected tint request");
}
@end

// UIKit owns the transition and final hierarchy. Deliver completion after setting that hierarchy,
// just as UIKit does for a completed push or a cancelled interactive pop.
@interface Transition : NSObject
@property (nonatomic, copy) void (^completion)(id);
- (BOOL)animateAlongsideTransition:(id)animation completion:(void (^)(id))completion;
@end
@implementation Transition
- (BOOL)animateAlongsideTransition:(id)animation completion:(void (^)(id))completion { self.completion = completion; return YES; }
@end
@interface PageFieldNotice : NSObject
@property (nonatomic, strong) UIView *accentPage;
@end
@implementation PageFieldNotice @end

static NSUInteger checks;
static void expect(BOOL ok, NSString *name) {
    checks++;
    if (!ok) HARNESS_FAIL(@"%@", name);
}
static void rgb(NSInteger wanted, NSString *name) {
    checks++;
    if (SGRAccentRGB() != wanted) HARNESS_FAIL(@"%@: got #%06lX, expected #%06lX", name, (long)SGRAccentRGB(), (long)wanted);
}
static void settings(BOOL automatic) {
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{
        SGRKeyAccent: @0x123456, SGRKeyAccentAuto: @(automatic),
        @"spotifyglass.accent": @0xABCDEF
    } forName:NSArgumentDomain];
    SGRAccentPreferencesChanged();
}
static void show(UIViewController *page) { front = page; SGRAccentRefreshContext(); }
static void deliver(NSUInteger index, UIColor *color) {
    void (^reply)(SGRPalette *) = replies[index];
    [replies removeObjectAtIndex:index];
    SGRPalette *palette = [SGRPalette new]; palette.fieldColor = color;
    reply(palette);
}
static double linear(double v) { return v <= .04045 ? v/12.92 : pow((v+.055)/1.055, 2.4); }
static NSInteger colorRGB(UIColor *color) {
    CGFloat r, g, b, a;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return (lround(r*255)<<16) | (lround(g*255)<<8) | lround(b*255);
}

static void checkSpotifyPick(void) {
    if (SGInt(SGRKeyAccent, SGRDefaultAccent) != -1)
        HARNESS_FAIL(@"stock launch input: %@", [NSUserDefaults.standardUserDefaults objectForKey:SGRKeyAccent]);
    SGRAccentStart();
    expect(SGRAccentColor() == nil, @"Picked/Spotify keeps the previous nil-token contract");
    UIColor *legacy = [UIColor colorWithRed:29/255.0 green:185/255.0 blue:84/255.0 alpha:1];
    expect(colorRGB(legacy) == 0x1DB954, @"Picked/Spotify leaves the old brand green exact");
    CAShapeLayer *shape = [CAShapeLayer layer]; shape.fillColor = legacy.CGColor;
    expect(colorRGB([UIColor colorWithCGColor:shape.fillColor]) == 0x1DB954, @"Picked/Spotify leaves layer colors exact");
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"fillColor"];
    animation.fromValue = (id)legacy.CGColor;
    expect(colorRGB([UIColor colorWithCGColor:(__bridge CGColorRef)animation.fromValue]) == 0x1DB954, @"Picked/Spotify leaves animation inputs exact");
    CGFloat r=29/255.0,g=185/255.0,b=84/255.0;
    expect(!SGRAccentSwap(&r,&g,&b) && r==29/255.0 && g==185/255.0 && b==84/255.0, @"disabled substitution does not alter components");
    // Enable live even though the effective fallback RGB is still Spotify's green.
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGRKeyAccent:@(-1),SGRKeyAccentAuto:@YES} forName:NSArgumentDomain];
    SGRAccentPreferencesChanged();
    UIViewController *page=[UIViewController new]; front=page;
    SGRAccentPublishPageColor(page.view,UIColor.yellowColor);
    UIColor *tracked = [UIColor colorWithRed:29/255.0 green:185/255.0 blue:84/255.0 alpha:1];
    expect(colorRGB(tracked) != 0x1DB954, @"live Automatic enable installs substitution");
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGRKeyAccent:@(-1),SGRKeyAccentAuto:@NO} forName:NSArgumentDomain];
    SGRAccentPreferencesChanged();
    expect(colorRGB(tracked) == 0x1DB954, @"disabling Automatic restores original legacy token, not a scaled current green");
    expect(colorRGB([UIColor colorWithRed:29/255.0 green:185/255.0 blue:84/255.0 alpha:1]) == 0x1DB954,
           @"new colors bypass already-installed hooks after disabling");
    printf("Picked Spotify: %lu checks passed\n",(unsigned long)checks);
}

int main(void) {
    @autoreleasepool {
        if ([NSProcessInfo.processInfo.arguments containsObject:@"stock"]) { checkSpotifyPick(); return 0; }
        replies = [NSMutableArray array];
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGRKeyAccent: @0x123456} forName:NSArgumentDomain];
        SGPrefsChanged();
        SGRAccentStart();
        rgb(0x123456, @"Automatic defaults off");
        UIViewController *a = [UIViewController new], *b = [UIViewController new], *noArt = [UIViewController new], *player = [UIViewController new];
        PageFieldNotice *field = [PageFieldNotice new]; field.accentPage = a.view;
        [NSNotificationCenter.defaultCenter postNotificationName:SGRFieldColorDidChangeNotification object:field userInfo:@{@"color": UIColor.yellowColor}];
        SGRAccentPublishPageColor(b.view, UIColor.whiteColor);
        SGRAccentPublishPageColor(noArt.view, nil);
        show(a);
        rgb(0x123456, @"page publication cannot change Picked");
        settings(YES);
        rgb(0xFFFF00, @"A owns foreground");

        UILabel *label = [UILabel new];
        label.textColor = [UIColor colorWithRed:30/255.0 green:215/255.0 blue:96/255.0 alpha:1];
        UIView *control = [UIView new]; control.tintColor = SGRAccentColor();
        CAShapeLayer *shape = [CAShapeLayer layer];
        CGFloat components[] = {30/255.0, 215/255.0, 96/255.0, 1};
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGColorRef green = CGColorCreate(space, components);
        shape.fillColor = green; CGColorRelease(green); CGColorSpaceRelease(space);
        show(b);
        rgb(0xFFFFFF, @"A to B");
        expect(colorRGB(label.textColor) == 0xFFFFFF, @"assigned token text follows B");
        expect(colorRGB(control.tintColor) == 0xFFFFFF, @"assigned control tint follows B");
        expect(colorRGB([UIColor colorWithCGColor:shape.fillColor]) == 0xFFFFFF, @"Lottie shape follows B");
        UIColor *constructed = [[UIColor alloc] initWithRed:30/255.0 green:215/255.0 blue:96/255.0 alpha:1];
        expect(colorRGB(constructed) == 0xFFFFFF, @"UIColor initializer preserves token behavior");

        Transition *pop = [Transition new];
        SGRAccentTrackTransition((id)pop);
        front = a; // interactive transition's tentative top, not a committed owner
        SGRAccentPublishPageColor(a.view, UIColor.cyanColor);
        rgb(0xFFFFFF, @"interactive pop retains committed B");
        front = b; pop.completion(nil);
        rgb(0xFFFFFF, @"cancelled pop returns to B");
        SGRAccentPublishPageColor(a.view, UIColor.yellowColor);
        rgb(0xFFFFFF, @"late A color cannot repaint B");

        trackURI = @"spotify:track:one";
        [observer playerStateDidChange:SGPlayerState()];
        coverTrack = trackURI; cover = [UIImage new];
        [NSNotificationCenter.defaultCenter postNotificationName:SGRNowPlayingArtworkDidChangeNotification object:nil];
        deliver(0, UIColor.cyanColor);
        show(noArt);
        rgb(0x00FFFF, @"no-color page falls back to playing cover");
        show(b); show(player);
        rgb(0x00FFFF, @"player open uses cover, not underlying page");
        show(b);
        rgb(0xFFFFFF, @"player close restores page");
        show(player);
        trackURI = @"spotify:track:two";
        [observer playerStateDidChange:SGPlayerState()];
        rgb(0x123456, @"new track without cover falls back to pick");
        coverTrack = trackURI; cover = [UIImage new];
        [NSNotificationCenter.defaultCenter postNotificationName:SGRNowPlayingArtworkDidChangeNotification object:nil];
        trackURI = @"spotify:track:three";
        [observer playerStateDidChange:SGPlayerState()];
        deliver(0, UIColor.yellowColor);
        rgb(0x123456, @"late previous track palette ignored");

        show(a);
        SGRAccentPublishPageColor(a.view, UIColor.blackColor);
        NSInteger result = SGRAccentRGB();
        double luminance = .2126*linear(((result>>16)&255)/255.0)+.7152*linear(((result>>8)&255)/255.0)+.0722*linear((result&255)/255.0);
        expect((luminance+.05)/.12 >= 4.5, @"dark artwork accent reaches 4.5:1 against the darkest allowed field boundary");
        expect((luminance+.05)/.05 >= 4.5, @"black glyph on automatic accent remains readable");
        settings(NO);
        rgb(0x123456, @"off restores exact picked color");
        expect(colorRGB(label.textColor) == 0x123456, @"live text returns to picked color");
        expect(SGRPickedAccentRGB() == 0x123456, @"automatic never overwrites saved pick");
        expect(SGInt(@"spotifyglass.accent", -1) == 0xABCDEF, @"Native accent is untouched");
        printf("appearance accent: %lu checks passed\n", (unsigned long)checks);
    }
    return 0;
}
