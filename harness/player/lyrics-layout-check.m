// The player's lyric viewport must not follow the artwork pager between tracks.
// lyrics-layout-check.sh includes the production measurement section unchanged.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static UIViewController *sg_info, *sg_duration;
static UIView *sg_titleElement;
static char kColumnKey;
static CGRect artworkArea, artworkCover;
static const CGFloat SGRSideMargin = 24, SGRGrid = 8;
static CGRect SGFrameIn(UIView *view, UIView *host) { return [view convertRect:view.bounds toView:host]; }
static CGRect SGRPlayerArtworkAreaIn(UIView *host) { return artworkArea; }
static CGRect SGRPlayerCoverFrameIn(UIView *host) { return artworkCover; }
static BOOL wideIn(UIView *host) { return NO; }
static CGRect wideColumn(UIView *host) { return CGRectZero; }

#include "lyrics-layout-production.inc"

int main(void) {
    @autoreleasepool {
        UIView *host = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 393, 852)];
        sg_info = [UIViewController new];
        sg_info.view = [[UIView alloc] initWithFrame:CGRectMake(0, 550, 393, 64)];
        sg_duration = [UIViewController new];
        sg_duration.view = [[UIView alloc] initWithFrame:CGRectMake(0, 614, 393, 40)];
        sg_titleElement = [[UIView alloc] initWithFrame:CGRectMake(24, 0, 260, 64)];
        [host addSubview:sg_info.view];
        [host addSubview:sg_duration.view];
        [sg_info.view addSubview:sg_titleElement];
        // Both sides of a native cover-page transition, plus the settled page.
        for (NSNumber *x in @[@0, @32, @(-62), @393, @(-393)]) {
            artworkArea = CGRectMake(x.doubleValue, 106, 393, 444);
            artworkCover = CGRectMake(x.doubleValue + 24, 150, 345, 345);
            SGRLyricsLayout layout = layoutIn(host);
            CGRect expected = CGRectMake(0, 206, 393, 400);
            if (!layout.ok || !CGRectEqualToRect(layout.stage, expected)) {
                NSLog(@"FAIL artwork x=%@: lyric viewport %@, expected %@", x,
                      NSStringFromCGRect(layout.stage), NSStringFromCGRect(expected));
                return 1;
            }
        }
        NSLog(@"PASS lyric viewport stays at {0,206,393,400} throughout cover paging");
    }
    return 0;
}
