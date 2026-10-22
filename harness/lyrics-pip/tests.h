#import <UIKit/UIKit.h>

void SGTestAssert(BOOL ok, NSString *what);
BOOL SGTestPump(BOOL (^ready)(void));
void SGTestSetting(NSString *key, id value);
void SGTestSetTrack(NSString *uri, NSString *artworkURL);
NSString *SGTestTrackURI(void);
void (^SGTestTakeArtwork(void))(UIImage *);
NSUInteger SGTestArtworkRequests(void);
UIImage *SGTestCover(void);
void SGTestBackground(void);
void SGTestSettings(void);
void SGTestLifecycle(void);
void SGTestNativeMenu(void);
void SGTestRedesignMenu(void);
void SGTestPiPState(BOOL enabled, BOOL active, BOOL starting);
NSUInteger SGTestDisabledAlerts(void);
UIView *SGTestSourceView(void);
