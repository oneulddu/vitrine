#import <Foundation/Foundation.h>
#import <objc/runtime.h>

BOOL SGHidden(NSString *key);
void SGRequireClasses(NSArray<NSString *> *names);
#define SGLog(...) ((void)0)
