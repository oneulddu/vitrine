// Point geometry shared by the expanded glass bar and its settings preview.
#import <UIKit/UIKit.h>

static const CGFloat SGRBarPlatterInsetPt = 21, SGRBarApartItemWidthPt = 62, SGRBarPlatterGapPt = 12;

static inline void SGRExpandedBarFrames(CGRect bounds, NSUInteger apartCount, CGRect *main, CGRect *apart) {
    *main = bounds;
    *apart = CGRectZero;
    if (!apartCount) return;
    CGFloat width = MIN(bounds.size.width / 2, apartCount * SGRBarApartItemWidthPt + 2 * SGRBarPlatterInsetPt);
    CGRectDivide(bounds, apart, main, width, CGRectMaxXEdge);
    main->size.width += 2 * SGRBarPlatterInsetPt - SGRBarPlatterGapPt;
}
