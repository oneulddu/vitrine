// Offline contracts shared by the Home, Search and Library headers and page cells.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../harness-fail.h"
#import "Core/SGViewTree.h"
#import "Redesigned/Kit/SGRRestyle.h"
#import "Redesigned/Kit/SGRField.h"

@interface HarnessRetrievalListStructuredData : UIView @end
@implementation HarnessRetrievalListStructuredData @end

@interface HarnessHome_EvoPageImpl13HomeStructure : UIView @end
@implementation HarnessHome_EvoPageImpl13HomeStructure @end
@interface HarnessBrowse_BrowsePageImpl15BrowseStructure : UIView @end
@implementation HarnessBrowse_BrowsePageImpl15BrowseStructure @end
@interface HarnessUnnamedContent : HarnessHome_EvoPageImpl13HomeStructure @end
@implementation HarnessUnnamedContent @end

static UIImageView *artwork(CGFloat width, UIImage *image) {
    UIImageView *view = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, width, 80)];
    view.image = image;
    return view;
}

static void checkHeaderArtwork(void) {
    UIView *root = [UIView new];
    UIImageView *firstEmpty = artwork(80, nil), *secondEmpty = artwork(100, nil);
    [root addSubview:firstEmpty];
    [root addSubview:secondEmpty];
    HARNESS_CHECK(SGRHeaderArtworkIn(root) == firstEmpty);

    UIImageView *filled = artwork(80, [UIImage new]);
    [secondEmpty addSubview:filled];
    HARNESS_CHECK(SGRHeaderArtworkIn(root) == filled);

    UIView *thresholdRoot = [UIView new];
    UIImageView *small = artwork(79, [UIImage new]), *boundary = artwork(80, [UIImage new]);
    [thresholdRoot addSubview:small];
    [thresholdRoot addSubview:boundary];
    HARNESS_CHECK(SGRHeaderArtworkIn(thresholdRoot) == boundary);
    [boundary removeFromSuperview];
    HARNESS_CHECK(SGRHeaderArtworkIn(thresholdRoot) == nil);
}

static void checkClassNames(void) {
    Class home = HarnessHome_EvoPageImpl13HomeStructure.class;
    Class browse = HarnessBrowse_BrowsePageImpl15BrowseStructure.class;
    HARNESS_CHECK(SGClassNamed(home, @"Home_EvoPageImpl13HomeStructure"));
    HARNESS_CHECK(!SGClassNamed(home, @"Browse_BrowsePageImpl15BrowseStructure"));
    HARNESS_CHECK(SGClassNamed(browse, @"Browse_BrowsePageImpl15BrowseStructure"));
    HARNESS_CHECK(!SGClassNamed(browse, @"Home_EvoPageImpl13HomeStructure"));
    HARNESS_CHECK(!SGClassNamed(HarnessUnnamedContent.class, @"Home_EvoPageImpl13HomeStructure"));
    HARNESS_CHECK(!SGClassNamed(Nil, @"Home_EvoPageImpl13HomeStructure"));
}

static void checkRememberedViews(void) {
    static char key;
    UIView *root = [UIView new], *branch = [UIView new];
    [root addSubview:branch];
    BOOL (^isImage)(UIView *) = ^BOOL(UIView *view) { return [view isKindOfClass:UIImageView.class]; };
    HARNESS_CHECK(SGFindRemembered(root, &key, isImage) == nil);
    UIImageView *nested = artwork(80, nil), *later = artwork(80, nil);
    [branch addSubview:nested];
    [root addSubview:later];
    HARNESS_CHECK(SGFindRemembered(root, &key, isImage) == nested);
    [nested removeFromSuperview];
    HARNESS_CHECK(SGFindRemembered(root, &key, isImage) == later);
    __weak UIImageView *released;
    @autoreleasepool {
        released = later;
        [later removeFromSuperview];
        later = nil;
    }
    HARNESS_CHECK(released == nil);
}

static void checkLabelText(void) {
    UIView *empty = [UIView new];
    [empty addSubview:[UILabel new]];
    HARNESS_CHECK(SGRFirstLabelText(empty) == nil);

    UIView *root = [UIView new];
    UILabel *whitespace = [UILabel new], *first = [UILabel new], *later = [UILabel new];
    whitespace.text = @" \t\n\r ";
    first.text = @" \nX\t ";
    first.hidden = YES;
    later.text = @"Later";
    [root addSubview:whitespace];
    [whitespace addSubview:first];
    [root addSubview:later];
    HARNESS_CHECK([SGRFirstLabelText(root) isEqualToString:@"X"]);
    HARNESS_CHECK([SGRFirstLabelText(first) isEqualToString:@"X"]);
}

void SGRRunKitChecks(void) {
    checkLabelText();
    checkHeaderArtwork();
    checkClassNames();
    checkRememberedViews();
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
    puts("PASS page Kit contracts: artwork, class names, weak lookup, cell lifecycle, titles, child lookup, masking, fields, track content");
    fflush(NULL);
}
