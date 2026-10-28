// Real Core preference gate plus the environment's public decision seam, no network requests.
#import "Core/SGOptionalWork.h"
#import <objc/runtime.h>
#import <Network/Network.h>

#define CHECK(x) do { if (!(x)) { fprintf(stderr, "FAIL %d: %s\n", __LINE__, #x); exit(1); } } while (0)
static NSUserDefaults *defaults;
static id isolatedDefaults(id self, SEL selector) { return defaults; }
static BOOL lowPowerOff(id self, SEL selector) { return NO; }
static NSProcessInfoThermalState cool(id self, SEL selector) { return NSProcessInfoThermalStateNominal; }

// Replace only the environmental boundary, not the production gate or its decision function.
// A real monitor is allocated but never started; its initial update is deterministic and offline.
void nw_path_monitor_start(nw_path_monitor_t monitor) {}
void nw_path_monitor_set_update_handler(nw_path_monitor_t monitor, nw_path_monitor_update_handler_t handler) {
    handler((nw_path_t)[NSObject new]);
}
nw_path_status_t nw_path_get_status(nw_path_t path) { return nw_path_status_satisfied; }
bool nw_path_is_constrained(nw_path_t path) { return false; }
bool nw_path_is_expensive(nw_path_t path) { return false; }

int main(void) {
    @autoreleasepool {
        NSString *suite = [@"vitrine.optional-check." stringByAppendingString:NSUUID.UUID.UUIDString];
        defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        method_setImplementation(class_getClassMethod(NSUserDefaults.class, @selector(standardUserDefaults)), (IMP)isolatedDefaults);
        method_setImplementation(class_getInstanceMethod(NSProcessInfo.class, @selector(isLowPowerModeEnabled)), (IMP)lowPowerOff);
        method_setImplementation(class_getInstanceMethod(NSProcessInfo.class, @selector(thermalState)), (IMP)cool);
        CHECK([defaults objectForKey:SGKeyLoadAhead] == nil);
        CHECK(SGOptionalWorkMayRun(NO));
        CHECK(SGOptionalWorkMayRun(YES));
        [defaults setBool:YES forKey:SGKeyLoadAhead];
        CHECK(SGOptionalWorkMayRun(NO));
        CHECK(SGOptionalWorkMayRun(YES));
        [defaults setBool:NO forKey:SGKeyLoadAhead];
        CHECK(!SGOptionalWorkMayRun(NO));
        CHECK(!SGOptionalWorkMayRun(YES));
        // Exhaust every environment combination with literal precedence expectations.
        for (int power = 0; power < 2; power++)
        for (int heat = 0; heat < 4; heat++)
        for (int path = 0; path < 2; path++)
        for (int constrained = 0; constrained < 2; constrained++)
        for (int expensive = 0; expensive < 2; expensive++)
        for (int permits = 0; permits < 2; permits++) {
            SGOptionalWorkReason expected = power ? SGOptionalWorkLowPower : heat >= 2 ? SGOptionalWorkHeat :
                !path ? SGOptionalWorkNoPath : constrained ? SGOptionalWorkConstrained :
                expensive && !permits ? SGOptionalWorkExpensive : SGOptionalWorkAllowed;
            CHECK(SGOptionalWorkReasonForInputs(power, heat, path, constrained, expensive, permits) == expected);
        }
        [defaults removePersistentDomainForName:suite];
        puts("optional gate: absent/on/off through the real gate and 128 environment combinations passed");
    }
    return 0;
}
