#import <Foundation/Foundation.h>

#define SGKeyLoadAhead @"spotifyglass.loadAhead"
@class SGModRow;
// Defined by Shared's settings composition, not Core.
SGModRow *SGLoadAheadRow(void);

typedef NS_ENUM(NSUInteger, SGOptionalWorkReason) {
    SGOptionalWorkAllowed,
    SGOptionalWorkLowPower,
    SGOptionalWorkHeat,
    SGOptionalWorkNoPath,
    SGOptionalWorkConstrained,
    SGOptionalWorkExpensive,
};

// Pure decision seam: callers/tests supply a coherent snapshot. Lyrics allow expensive paths;
// artwork does not. An unknown path is unavailable until the monitor's first update.
SGOptionalWorkReason SGOptionalWorkReasonForInputs(BOOL lowPower, NSProcessInfoThermalState thermal,
                                                  BOOL pathSatisfied, BOOL constrained, BOOL expensive,
                                                  BOOL allowsExpensive);

// Any queue. Only for advance work, never a current-track or visible-page request.
BOOL SGOptionalWorkMayRun(BOOL allowsExpensive);
BOOL SGOptionalWorkNetworkExpensive(void);
