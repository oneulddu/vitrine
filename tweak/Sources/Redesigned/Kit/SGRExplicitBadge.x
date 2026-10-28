// Spotify 9.1.90 binary: exact component identifier and retrieval-row class. Never match label text.
// A transparent drawing mask, not UIView.hidden/alpha: keep geometry and accessibility participation intact.
#import "Core/SGCore.h"
#import "SGRAccent.h"

static NSHashTable<UIView *> *badges;
static char originalMaskKey, hiddenMaskKey;
static BOOL applying;

static BOOL explicitBadge(UIView *view) {
    if ([view.accessibilityIdentifier isEqualToString:@"Components.UI.ExplicitIcon"]) return YES;
    Class retrieval = NSClassFromString(@"_TtCCC36CreativeWorkPlatform_RetrievalRowKit21RetrievalRowElementUI10BadgesViewP33_9D5FF3EB21C9757CC8B47C2445B48C7B13ExplicitBadge");
    return retrieval && [view isKindOfClass:retrieval];
}

static void applyBadge(UIView *view) {
    id original = objc_getAssociatedObject(view, &originalMaskKey);
    BOOL hide = explicitBadge(view) && SGFlag(SGRKeyHideExplicit, NO);
    if (hide && !original) {
        original = view.layer.mask ?: NSNull.null;
        objc_setAssociatedObject(view, &originalMaskKey, original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!badges) badges = [NSHashTable weakObjectsHashTable];
    if (explicitBadge(view)) [badges addObject:view];
    if (!original) return;
    CALayer *mask = objc_getAssociatedObject(view, &hiddenMaskKey);
    if (hide && !mask) {
        mask = [CALayer layer];
        objc_setAssociatedObject(view, &hiddenMaskKey, mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    applying = YES;
    view.layer.mask = hide ? mask : original == NSNull.null ? nil : original;
    applying = NO;
    if (!hide) {
        objc_setAssociatedObject(view, &originalMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &hiddenMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

void SGRRefreshExplicitBadges(void) {
    for (UIView *view in badges.allObjects) applyBadge(view);
}

%hook UIView
- (void)layoutSubviews {
    %orig;
    if (explicitBadge(self) || objc_getAssociatedObject(self, &originalMaskKey)) applyBadge(self);
}
- (void)setAccessibilityIdentifier:(NSString *)identifier {
    %orig;
    if (explicitBadge(self) || objc_getAssociatedObject(self, &originalMaskKey)) applyBadge(self);
}
%end

%hook CALayer
- (void)setMask:(CALayer *)mask {
    id delegate = self.delegate;
    if (!applying && [delegate isKindOfClass:UIView.class] && ((UIView *)delegate).layer == self &&
        explicitBadge(delegate) && SGFlag(SGRKeyHideExplicit, NO)) {
        objc_setAssociatedObject(delegate, &originalMaskKey, mask ?: NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        applyBadge(delegate);
        return;
    }
    %orig(mask);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{ SGPrefsChanged(); SGRRefreshExplicitBadges(); });
    }];
}
