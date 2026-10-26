// Offline contracts shared by the Home, Search and Library headers and page cells.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../harness-fail.h"
#import "Redesigned/Kit/SGRRestyle.h"
#import "Redesigned/Kit/SGRField.h"

@interface HarnessRetrievalListStructuredData : UIView @end
@implementation HarnessRetrievalListStructuredData @end

void SGRRunKitChecks(void) {
    static char cellKey, otherKey, titleKey, fieldKey;
    UICollectionViewCell *cell = [[UICollectionViewCell alloc] initWithFrame:CGRectMake(0, 0, 320, 0)];
    cell.contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    objc_setAssociatedObject(cell, &otherKey, @23, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SGRCollapseCell(cell, 84, &cellKey);
    HARNESS_CHECK(CGRectEqualToRect(cell.contentView.frame, CGRectMake(0, 0, 320, 84)));
    HARNESS_CHECK(cell.contentView.hidden && cell.clipsToBounds && cell.accessibilityElementsHidden);
    HARNESS_CHECK(!(cell.contentView.autoresizingMask & UIViewAutoresizingFlexibleHeight));
    HARNESS_CHECK([objc_getAssociatedObject(cell, &cellKey) isEqual:@84]);
    cell.bounds = CGRectMake(0, 0, 360, 72);
    SGRRestoreCell(cell, &cellKey);
    HARNESS_CHECK(CGRectEqualToRect(cell.contentView.frame, CGRectMake(0, 0, 360, 72)));
    HARNESS_CHECK(!cell.contentView.hidden && !cell.clipsToBounds && !cell.accessibilityElementsHidden);
    HARNESS_CHECK(cell.contentView.autoresizingMask == (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight));
    HARNESS_CHECK(!objc_getAssociatedObject(cell, &cellKey) && [objc_getAssociatedObject(cell, &otherKey) isEqual:@23]);
    // Album uses an array under its key, not the scalar used by the other three pages.
    objc_setAssociatedObject(cell, &cellKey, @[@84, @16, @320, @"large"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SGRRestoreCell(cell, &cellKey);
    HARNESS_CHECK(!objc_getAssociatedObject(cell, &cellKey));

    UIView *host = [UIView new];
    UILabel *title = SGRLargeTitleIn(host, &titleKey);
    HARNESS_CHECK([title.textColor isEqual:UIColor.whiteColor] && title.accessibilityTraits == UIAccessibilityTraitHeader);
    HARNESS_CHECK(title.adjustsFontSizeToFitWidth && title.minimumScaleFactor == 0.6f && !title.userInteractionEnabled);
    title.text = @"Kept title";
    title.textColor = UIColor.redColor;
    [title removeFromSuperview];
    HARNESS_CHECK(SGRLargeTitleIn(host, &titleKey) == title && title.superview == host);
    HARNESS_CHECK([title.text isEqual:@"Kept title"] && [title.textColor isEqual:UIColor.redColor]);

    UIView *wrapper = [UIView new];
    [host insertSubview:wrapper atIndex:0];
    UILabel *nested = [UILabel new];
    [wrapper addSubview:nested];
    UILabel *last = [UILabel new];
    [host addSubview:last];
    HARNESS_CHECK(SGRChildNamed(host, @"Label") == title);
    [title removeFromSuperview];
    [last removeFromSuperview];
    HARNESS_CHECK(SGRChildNamed(host, @"Label") == nil);
    HARNESS_CHECK(SGRChildNamed(nil, @"Label") == nil);

    UIView *blank = [UIView new];
    SGRBlankView(blank);
    HARNESS_CHECK(!blank.hidden && !blank.layer.hidden && blank.layer.mask != nil);
    HARNESS_CHECK(!blank.userInteractionEnabled && blank.accessibilityElementsHidden);
    CALayer *mask = blank.layer.mask;
    SGRConcealView(blank);
    HARNESS_CHECK(blank.layer.hidden && blank.layer.mask == mask);
    blank.hidden = NO;
    SGRBlankView(blank);
    HARNESS_CHECK(blank.layer.mask == mask && !blank.layer.hidden);

    UIView *page = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 640)];
    UIView *content = [UIView new];
    [page addSubview:content];
    SGRArtworkField *field = SGRPageFieldIn(page, &fieldKey, @"check");
    HARNESS_CHECK(page.subviews.firstObject == field && CGRectEqualToRect(field.frame, CGRectMake(0, 0, 320, 640)));
    HARNESS_CHECK(field.mainColor && UIEdgeInsetsEqualToEdgeInsets(field.bleed, UIEdgeInsetsMake(600, 0, 600, 0)));
    HARNESS_CHECK(SGRPageFieldOn(content, &fieldKey) == field && SGRPageFieldOn(content, &otherKey) == nil);
    [page sendSubviewToBack:content];
    page.bounds = CGRectMake(0, 0, 400, 800);
    HARNESS_CHECK(SGRPageFieldIn(page, &fieldKey, @"check") == field);
    HARNESS_CHECK(page.subviews.firstObject == field && CGRectEqualToRect(field.frame, CGRectMake(0, 0, 400, 800)));

    HARNESS_CHECK(SGRIsTrackContent([HarnessRetrievalListStructuredData new]));
    HARNESS_CHECK(!SGRIsTrackContent([UIView new]) && !SGRIsTrackContent(nil));
    puts("PASS page Kit contracts: cell lifecycle, titles, child lookup, masking, fields, track content");
    fflush(NULL);
}
