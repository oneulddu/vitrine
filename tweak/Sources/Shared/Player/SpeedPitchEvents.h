// Control-side event from the authoritative audio-effects setters, delivered synchronously on main.
// Shared as a literal so standalone audio-effects harnesses need no player implementation to link.
#import <Foundation/Foundation.h>
#define SGSpeedPitchReverbDidChange @"spotifyglass.speedPitch.reverbDidChange"
