#import <Foundation/Foundation.h>
@class SPTPlayerState, SGKaraokeLine;
void check(BOOL ok, NSString *what);
void runFor(NSTimeInterval seconds);
SGKaraokeLine *lineOf(NSString *text, NSInteger start, NSInteger end);
SPTPlayerState *harnessState(NSString *uri, NSString *title);
void harnessLines(NSArray *lines);
void harnessMetadata(NSDictionary *metadata);
NSDictionary *harnessSystem(void);
NSUInteger harnessSets(void);
void artworkChecks(void);
void activityChecks(void);
extern NSString *harnessLanguage;
extern NSDictionary *harnessTranslations;
extern BOOL harnessHoldTranslation;
extern NSUInteger harnessAutomaticTranslations;
void harnessDeliverTranslations(void);
