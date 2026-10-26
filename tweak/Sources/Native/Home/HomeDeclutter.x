// Home declutter: sections of Home collapsed and the filter pills hidden, one switch each on the Home &
// Library page. A section is an Element_List cell; a hidden one reports zero height when the list sizes
// it, so the list closes up around it.
//
// Trees (trees/home*.txt): every section is a CollectionViewCell whose content view names the page
// (Home_EvoPageImpl) and whose subtree names the section.
#import "Core/SGCore.h"
#import "Home.h"
#import "Native/Declutter/Declutter.h"

static const SGNativeMarkerRule sections[] = {
    {@"Home_AnchorsAndShortcutsKit", SGHideHomeShortcuts},
    {@"Discovery_PromoElement", SGHideHomePromo},
    {@"Discovery_PreviewElement", SGHideHomePreviews},
    {@"Discovery_DJElement", SGHideHomeDJ},
};

enum { kSections = sizeof(sections) / sizeof(sections[0]) };

// Whether the cell is a section of Home: its first view names the page. Spotify's cell has held it as its own
// first subview (Redesigned/Home/HomeSections.x) and as its content view's (Native/Player/PlayerDeclutter.x).
static BOOL onHome(UICollectionViewCell *cell) {
    return SGClassNamed(cell.subviews.firstObject.class, @"Home_EvoPageImpl")
        || SGClassNamed(cell.contentView.subviews.firstObject.class, @"Home_EvoPageImpl");
}

static NSString *hiddenKeyFor(UICollectionViewCell *cell) {
    if (!SGNativeAnyMarkerHidden(sections, kSections) || !onHome(cell)) return nil;
    // A cell inside another section's list: the outer section decides.
    for (UIView *v = cell.superview; v; v = v.superview) {
        if ([v isKindOfClass:cell.class]) return nil;
    }
    return SGNativeHiddenMarkerIn(cell, sections, kSections);
}

%hook _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *result = %orig;
    NSString *key = hiddenKeyFor((UICollectionViewCell *)self);
    if (!key) return result;
    result.size = CGSizeMake(result.size.width, 0);
    ((UIView *)self).clipsToBounds = YES;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"home: collapsed the first section, %@", key); });
    return result;
}
%end

%hook _TtC14Home_PillUIKit14PillScrollView
- (void)didMoveToWindow {
    %orig;
    if (SGHidden(SGHideHomePills)) ((UIView *)self).hidden = YES;
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC12Element_List18CollectionViewCell",
        @"_TtC14Home_PillUIKit14PillScrollView",
    ]);
}
