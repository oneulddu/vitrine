#import <os/lock.h>
#import "SGSingCommands.h"

static os_unfair_lock sg_lock = OS_UNFAIR_LOCK_INIT;
static SGSingCommand sg_command;
static const double kLandedNear = 0.3;

void SGSingCommandBegin(SGSingEngine *engine, NSString *track, double target, CFAbsoluteTime at) {
    os_unfair_lock_lock(&sg_lock);
    sg_command = (SGSingCommand){sg_command.generation + 1, at, target, track};
    if (engine) SGSingEngineSetLeadCap(engine, 0);
    os_unfair_lock_unlock(&sg_lock);
}

SGSingCommand SGSingCommandRead(void) {
    os_unfair_lock_lock(&sg_lock);
    SGSingCommand command = sg_command;
    os_unfair_lock_unlock(&sg_lock);
    return command;
}

BOOL SGSingCommandLanded(SGSingCommand command, NSString *track, CFAbsoluteTime stamp, double position) {
    if (!command.at || !isfinite(stamp) || stamp < command.at) return NO;
    return command.target < 0 || (track && command.track && ![track isEqualToString:command.track])
           || (position >= 0 && fabs(position - command.target) < kLandedNear);
}

BOOL SGSingCommandFinish(SGSingCommand command) {
    os_unfair_lock_lock(&sg_lock);
    BOOL current = sg_command.at && sg_command.generation == command.generation;
    if (current) {
        sg_command.at = 0;
        sg_command.track = nil;
    }
    os_unfair_lock_unlock(&sg_lock);
    return current;
}

void SGSingCommandCap(SGSingEngine *engine, double seconds) {
    os_unfair_lock_lock(&sg_lock);
    SGSingEngineSetLeadCap(engine, sg_command.at ? 0 : seconds);
    os_unfair_lock_unlock(&sg_lock);
}
