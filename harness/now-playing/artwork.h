#import <Foundation/Foundation.h>
@class SPTPlayerState, SGKaraokeLine;
void check(BOOL ok, NSString *what);
void runFor(NSTimeInterval seconds);
SGKaraokeLine *lineOf(NSString *text, NSInteger start, NSInteger end);
SPTPlayerState *harnessState(NSString *uri, NSString *title);
void harnessLines(NSArray *lines);
NSDictionary *harnessSystem(void);
NSUInteger harnessSets(void);
void artworkChecks(void);
