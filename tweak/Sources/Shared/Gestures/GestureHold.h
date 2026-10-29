// Hold either side of the player's cover to play faster until the finger lifts: the switch, the speed picked from
// a short list, and the words that name it. The hold itself is each look's (SGCoverHold in Native/Player/
// PlayerGestures.x, SGRCoverHold in Redesigned/Player/PlayerArtwork.x); both read what is here when a hold begins.
// Foundation only, so a host check can run it (harness/gesture-hold).
#import <Foundation/Foundation.h>

#define SGKeyGestureHold @"spotifyglass.gestures.hold"
#define SGKeyGestureHoldSpeed @"spotifyglass.gestures.hold.speed"

// The speeds a hold can play at, in the order of the list the Gestures page shows.
NSArray<NSNumber *> *SGGestureHoldSpeedChoices(void);

// On until switched off, independent of the double tap's switch.
BOOL SGGestureHoldEnabled(void);
// The stored index into the choices, an out-of-range one brought to the nearest valid index; 2x when unset.
NSInteger SGGestureHoldSpeedChoice(void);
double SGGestureHoldSpeed(void);

// "2×", "1.5×": the speed as the badge and the Gestures page write it.
NSString *SGGestureHoldSpeedLabel(double speed);
// What VoiceOver is told when a hold begins: "Playing at 1.5 times speed".
NSString *SGGestureHoldAnnouncement(double speed);
