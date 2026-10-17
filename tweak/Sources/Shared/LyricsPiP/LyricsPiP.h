// Opt-in, user-started lyrics PiP. All calls and the notification are on the main thread.
// The engine owns its source view independently of either look's lyrics screen.
#import <UIKit/UIKit.h>

#define SGKeyLyricsPiP @"spotifyglass.lyrics.pip"
@class SGModRow;
SGModRow *SGLyricsPiPRow(void);
BOOL SGLyricsPiPEnabled(void);       // launch-time flag; querying it creates nothing
BOOL SGLyricsPiPActive(void);
BOOL SGLyricsPiPStarting(void);
void SGLyricsPiPToggle(UIView *from); // user tap only; also cancels a pending start
extern NSNotificationName const SGLyricsPiPDidChangeNotification;
