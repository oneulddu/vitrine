// The hairline under a Your Library row (Redesigned/Library/LibraryRows.x) in a cell of the real class name:
// a 402x80 row with a 64pt artwork inset 16 (trees/clean/library/03.txt). Left to right the line starts 12pt
// after the artwork and runs to the right edge; right to left the artwork is on the right and the line runs from
// the left edge to 12pt before it. Exits nonzero on the first failed check.
#import <UIKit/UIKit.h>
#import "../harness-fail.h"

@interface _TtC21YourLibrary_CommonKit47YourLibrarySwipeableCollectionViewCellContainer : UIView @end
@implementation _TtC21YourLibrary_CommonKit47YourLibrarySwipeableCollectionViewCellContainer
- (void)layoutSubviews { [super layoutSubviews]; }
@end

// Before every %ctor, so the redesign's gate reads on.
__attribute__((constructor(101))) static void sgr_rowsDefaults(void) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.redesign"];
}

static CGRect hairlineOf(BOOL rtl) {
    UIView *cell = [[_TtC21YourLibrary_CommonKit47YourLibrarySwipeableCollectionViewCellContainer alloc] initWithFrame:CGRectMake(0, 0, 402, 80)];
    cell.semanticContentAttribute = rtl ? UISemanticContentAttributeForceRightToLeft : UISemanticContentAttributeForceLeftToRight;
    UIView *artwork = [[UIView alloc] initWithFrame:CGRectMake(rtl ? 402 - 16 - 64 : 16, 8, 64, 64)];
    artwork.accessibilityIdentifier = @"Artwork.Row.Library";
    [cell addSubview:artwork];
    [cell layoutSubviews];
    CALayer *line = nil;
    for (CALayer *layer in cell.layer.sublayers) if (CGRectGetHeight(layer.frame) < 1) line = layer;
    if (!line || line.hidden) HARNESS_FAIL(@"%@: the row has no hairline", rtl ? @"right to left" : @"left to right");
    return line.frame;
}

static void expect(NSString *what, CGRect line, CGFloat from, CGFloat to) {
    if (fabs(CGRectGetMinX(line) - from) > 0.01 || fabs(CGRectGetMaxX(line) - to) > 0.01) {
        HARNESS_FAIL(@"%@: the hairline spans %.1f..%.1f, expected %.1f..%.1f", what, CGRectGetMinX(line), CGRectGetMaxX(line), from, to);
    }
    NSLog(@"[harness] %@: hairline %.1f..%.1f", what, CGRectGetMinX(line), CGRectGetMaxX(line));
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        expect(@"left to right", hairlineOf(NO), 92, 402);
        expect(@"right to left", hairlineOf(YES), 0, 310);
        NSLog(@"[harness] PASS rows");
        fprintf(stderr, "[harness] PASS rows\n");
    }
    return 0;
}
