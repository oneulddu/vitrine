// The hold to play faster's switch, speed and wording; see GestureHold.h.
#import "Core/SGLocalize.h"
#import "Core/SGPrefs.h"
#import "GestureHold.h"

static const NSInteger kDefaultHoldSpeedChoice = 1;   // 2×, the speed the hold always had

NSArray<NSNumber *> *SGGestureHoldSpeedChoices(void) {
    return @[@1.5, @2, @3];
}

BOOL SGGestureHoldEnabled(void) {
    return SGEnabled(SGKeyGestureHold);
}

NSInteger SGGestureHoldSpeedChoice(void) {
    NSInteger choice = SGInt(SGKeyGestureHoldSpeed, kDefaultHoldSpeedChoice);
    return MAX(0, MIN((NSInteger)SGGestureHoldSpeedChoices().count - 1, choice));
}

double SGGestureHoldSpeed(void) {
    return SGGestureHoldSpeedChoices()[(NSUInteger)SGGestureHoldSpeedChoice()].doubleValue;
}

NSString *SGGestureHoldSpeedLabel(double speed) {
    return [NSString stringWithFormat:SGL(@"settings.gestures.hold_speed.format", @"%g×"), speed];
}

NSString *SGGestureHoldAnnouncement(double speed) {
    return [NSString stringWithFormat:SGL(@"settings.gestures.hold_announcement.format", @"Playing at %g times speed"), speed];
}
