#import "Localization.h"
#include <dlfcn.h>

NSString *SAPL(NSString *key,NSString *english) {
    // Do not cache a missing export: the companion can load before Vitrine.
    NSString *(*localize)(NSString *,NSString *)=dlsym(RTLD_DEFAULT,"SGL");
    return localize ? localize(key,english) : english;
}
