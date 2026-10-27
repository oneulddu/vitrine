// The native look's recent accent colors (Appearance.h): the list rules alone, stored by AppearanceSettings.m. The
// redesign keeps its own under its own key (Redesigned/Kit/SGRAccentHistory.m).
#import "Core/SGPrefs.h"
#import "Appearance.h"

static BOOL kept(NSInteger rgb) {
    return rgb >= 0 && rgb <= 0xFFFFFF && rgb != SGSpotifyGreen;
}

NSArray<NSNumber *> *SGAccentRecentFrom(id stored) {
    NSMutableArray<NSNumber *> *recent = [NSMutableArray array];
    if (![stored isKindOfClass:NSArray.class]) return recent;
    for (id entry in (NSArray *)stored) {
        // A boolean or a fraction is a number to NSNumber, not a color.
        if (![entry isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)entry) == CFBooleanGetTypeID()) continue;
        double value = [entry doubleValue];
        if (value != floor(value) || value < 0 || value > 0xFFFFFF) continue;
        NSInteger rgb = (NSInteger)value;
        if (!kept(rgb) || [recent containsObject:@(rgb)]) continue;
        [recent addObject:@(rgb)];
        if (recent.count == SGAccentRecentLimit) break;
    }
    return recent;
}

NSArray<NSNumber *> *SGAccentRecentAdding(NSArray<NSNumber *> *recent, NSInteger rgb, NSInteger current) {
    if (rgb == current || !kept(rgb)) return recent;
    NSMutableArray<NSNumber *> *next = [recent mutableCopy];
    [next removeObject:@(rgb)];
    [next insertObject:@(rgb) atIndex:0];
    while (next.count > SGAccentRecentLimit) [next removeLastObject];
    return next;
}
