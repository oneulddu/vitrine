// Kit owns the effective accent. Fields own page colors; the existing artwork bridge owns cover identity.
// No fetching here. Navigation commits only when its transition ends, including a cancelled interactive pop.
#import "SGRAccent.h"
#import "SGRBridges.h"
#import "SGRPalette.h"
#import "SGRField.h"
#import "Core/SGPrefs.h"
#import "Core/SGTopController.h"
#import <objc/runtime.h>
#import <stdatomic.h>

NSNotificationName const SGRAccentDidChangeNotification = @"spotifyglass.redesign.accent.didChange";
static atomic_long effective = SGRDefaultAccent;
static atomic_bool substituting = true;
static char tokenKey, cgTokenKey;

NSInteger SGRPickedAccentRGB(void) {
    NSInteger rgb = SGInt(SGRKeyAccent, SGRDefaultAccent);
    return rgb >= 0 && rgb <= 0xFFFFFF ? rgb : SGSpotifyGreen;
}

NSInteger SGRAccentRGB(void) { return atomic_load(&effective); }
BOOL SGRAccentSubstitutionEnabled(void) { return atomic_load(&substituting); }

@implementation SGRAccentToken
- (instancetype)initWithAlpha:(CGFloat)alpha shade:(CGFloat)shade originalRGB:(NSInteger)originalRGB {
    if ((self = [super init])) { _alpha = alpha; _shade = shade; _originalRGB = originalRGB; }
    return self;
}
- (CGColorRef)copyCGColorForRGB:(NSInteger)rgb shade:(CGFloat)shade CF_RETURNS_RETAINED {
    CGFloat rgba[] = {((rgb >> 16) & 255)/255.0 * shade, ((rgb >> 8) & 255)/255.0 * shade,
                      (rgb & 255)/255.0 * shade, _alpha};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGColorRef color = CGColorCreate(space, rgba);
    CGColorSpaceRelease(space);
    objc_setAssociatedObject((__bridge id)color, &cgTokenKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return color;
}
- (CGColorRef)copyCGColorForRGB:(NSInteger)rgb {
    return [self copyCGColorForRGB:rgb shade:_shade];
}
- (CGColorRef)copyGlobalCGColor {
    return SGRAccentSubstitutionEnabled() ? [self copyCGColorForRGB:SGRAccentRGB()]
        : [self copyCGColorForRGB:_originalRGB shade:1];
}
- (UIColor *)color {
    UIColor *color = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        CGColorRef cg = [self copyGlobalCGColor];
        UIColor *resolved = [UIColor colorWithCGColor:cg];
        CGColorRelease(cg);
        objc_setAssociatedObject(resolved, &tokenKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return resolved;
    }];
    objc_setAssociatedObject(color, &tokenKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return color;
}
@end

UIColor *SGRAccentTokenColor(CGFloat alpha, CGFloat shade) {
    return [[[SGRAccentToken alloc] initWithAlpha:alpha shade:shade originalRGB:SGSpotifyGreen] color];
}
SGRAccentToken *SGRAccentSource(UIColor *color) { return objc_getAssociatedObject(color, &tokenKey); }
SGRAccentToken *SGRAccentMarkedCGSource(CGColorRef color) { return objc_getAssociatedObject((__bridge id)color, &cgTokenKey); }
BOOL SGRAccentIsToken(UIColor *color) { return SGRAccentSource(color) != nil; }
UIColor *SGRAccentColor(void) { return SGRAccentSubstitutionEnabled() ? SGRAccentTokenColor(1, 1) : nil; }

static double linear(double component) {
    return component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4);
}

// Fields are bounded to relative luminance 0.07 (SGRPalette). 0.50 leaves a quantization margin
// above 4.5:1 on those fields, and > 10:1 for black glyphs on accent-filled controls.
static NSInteger readable(UIColor *color) {
    CGFloat r, g, b, a;
    if (!color || ![color getRed:&r green:&g blue:&b alpha:&a] || a == 0) return -1;
    double low = 0, high = 1;
    for (NSUInteger i = 0; i < 24; i++) {
        double mix = (low + high) / 2;
        double luminance = 0.2126 * linear(r + (1-r)*mix) + 0.7152 * linear(g + (1-g)*mix) + 0.0722 * linear(b + (1-b)*mix);
        if (luminance < 0.50) low = mix; else high = mix;
    }
    return (lround((r + (1-r)*high)*255) << 16) | (lround((g + (1-g)*high)*255) << 8) | lround((b + (1-b)*high)*255);
}

@interface SGRAccentContext : NSObject <SGPlayerStateObserver>
@property (nonatomic, strong) NSMapTable<UIView *, id> *pages;
@property (nonatomic, weak) UIView *front;
@property (nonatomic, weak) id<UIViewControllerTransitionCoordinator> transition;
@property (nonatomic) BOOL navigating;
@property (nonatomic) NSInteger cover;
@property (nonatomic, copy) NSString *track;
@property (nonatomic, strong) UIImage *image;
@property (nonatomic) NSUInteger generation;
- (void)refresh;
- (void)artwork;
- (void)apply;
@end

static SGRAccentContext *context;
static SGRAccentContext *owner(void) {
    if (!context) {
        context = [SGRAccentContext new];
        context.pages = [NSMapTable weakToStrongObjectsMapTable];
        context.cover = -1;
    }
    return context;
}

@implementation SGRAccentContext
- (void)apply {
    NSInteger pick = SGInt(SGRKeyAccent, SGRDefaultAccent);
    BOOL requested = SGFlag(SGRKeyAccentAuto, NO) || (pick >= 0 && pick <= 0xFFFFFF);
    // The constructor applies preferences before installing paint hooks. Only a stock launch
    // lacks those hooks; a later switch to stock must not revoke their launch-time availability.
    static BOOL availableAtLaunch;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ availableAtLaunch = requested; });
    BOOL enabled = availableAtLaunch && requested;
    BOOL wasEnabled = atomic_exchange(&substituting, enabled);
    NSInteger rgb = enabled ? SGRPickedAccentRGB() : SGSpotifyGreen;
    if (enabled && SGFlag(SGRKeyAccentAuto, NO)) {
        NSInteger page = -1;
        // The closest registered ancestor owns the front, not whichever field most recently laid out.
        for (UIView *view = self.front; view; view = view.superview) {
            id color = [self.pages objectForKey:view];
            if (!color) continue;
            page = color == NSNull.null ? -1 : readable(color);
            break;
        }
        if (page >= 0) rgb = page;
        else if (self.cover >= 0) rgb = self.cover;
    }
    NSInteger before = atomic_exchange(&effective, rgb);
    if (before != rgb || wasEnabled != enabled) [NSNotificationCenter.defaultCenter postNotificationName:SGRAccentDidChangeNotification object:nil];
}
- (void)refresh {
    if (self.navigating || self.transition) return;
    self.front = SGTopControllerInWindow(SGAppWindow(), nil, nil).viewIfLoaded;
    [self apply];
}
- (void)artwork {
    if (!SGRAccentSubstitutionEnabled() || !SGFlag(SGRKeyAccentAuto, NO)) return;
    NSString *track = nil;
    UIImage *image = SGRNowPlayingArtwork(&track, NULL);
    NSString *current = SGURIString(SGPlayerState().track.URI);
    if (!image || !current.length || ![track isEqualToString:current] || image == self.image) return;
    self.image = image;
    NSUInteger generation = ++self.generation;
    [SGRPalette paletteForImage:image request:(SGRPaletteRequest){.mainColor = YES} completion:^(SGRPalette *palette) {
        if (generation != self.generation || ![current isEqualToString:SGURIString(SGPlayerState().track.URI)]) return;
        self.cover = readable(palette.fieldColor);
        [self apply];
    }];
}
- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *track = SGURIString(state.track.URI);
    if (![track isEqualToString:self.track]) {
        self.track = track;
        self.image = nil;
        self.cover = -1;
        ++self.generation;
        [self apply];
    }
    [self artwork];
}
@end

void SGRAccentPublishPageColor(UIView *page, UIColor *color) {
    if (!page) return;
    SGRAccentContext *accent = owner();
    [accent.pages setObject:color ?: NSNull.null forKey:page];
    [accent refresh];
}

void SGRAccentRefreshContext(void) { [owner() refresh]; }
void SGRAccentNavigationWillChange(void) { owner().navigating = YES; }
void SGRAccentNavigationDidChange(id<UIViewControllerTransitionCoordinator> transition) {
    SGRAccentTrackTransition(transition);
    owner().navigating = NO;
    [owner() refresh];
}

void SGRAccentTrackTransition(id<UIViewControllerTransitionCoordinator> transition) {
    if (!transition || owner().transition == transition) return;
    owner().transition = transition;
    BOOL registered = [transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> result) {
        if (owner().transition != transition) return;
        owner().transition = nil;
        // UIKit's settled hierarchy is authoritative on success AND cancellation.
        [owner() refresh];
    }];
    // UIKit may still expose a coordinator after it has stopped accepting completions.
    if (!registered && owner().transition == transition) owner().transition = nil;
}

void SGRAccentPreferencesChanged(void) {
    SGPrefsChanged();
    [owner() apply];
    [owner() artwork];
}

void SGRAccentStart(void) {
    static BOOL started;
    if (started) return;
    started = YES;
    SGRAccentContext *accent = owner();
    SGAddPlayerStateObserver(accent);
    [accent playerStateDidChange:SGPlayerState()];
    [accent refresh];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:SGRFieldColorDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        SGRArtworkField *field = note.object;
        // Only SGRPageFieldIn supplies an accentPage. A player field is not a browsing page.
        if (field.accentPage) SGRAccentPublishPageColor(field.accentPage, note.userInfo[@"color"]);
    }];
    [center addObserverForName:SGRNowPlayingArtworkDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        [accent artwork];
    }];
    [center addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{ SGRAccentPreferencesChanged(); });
    }];
}
