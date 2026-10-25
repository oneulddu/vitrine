// Pending Spotify commands and the lead cap they hold. Off the render thread only.
// A snapshot owns its track; completing an older snapshot never clears a newer command.
#import "SGSingEngine.h"

typedef struct {
    uint64_t generation;
    CFAbsoluteTime at;
    double target;
    NSString *track;
} SGSingCommand;

void SGSingCommandBegin(SGSingEngine *engine, NSString *track, double target, CFAbsoluteTime at);
SGSingCommand SGSingCommandRead(void);
BOOL SGSingCommandLanded(SGSingCommand command, NSString *track, CFAbsoluteTime stamp, double position);
BOOL SGSingCommandFinish(SGSingCommand command);
// Applies the queue's end cap, unless a command still holds the lead at zero.
void SGSingCommandCap(SGSingEngine *engine, double seconds);
