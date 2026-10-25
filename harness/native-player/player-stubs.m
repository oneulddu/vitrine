// Player services outside the artwork and tap-routing regressions.
#import "Shared/Gestures/Gestures.h"
#import "Shared/Haptics/Haptics.h"
#import "Shared/Player/SpeedPitch.h"

__weak UIView *sg_npvBackdropRoot;
void SGGestureAttach(UIView *host) {}
BOOL SGPlayerSpeedAllowed(void) { return NO; }
double SGPlayerSpeed(void) { return 1; }
void SGSetPlayerSpeed(double speed) {}
void SGPlayFeedback(SGFeedback feedback) {}
