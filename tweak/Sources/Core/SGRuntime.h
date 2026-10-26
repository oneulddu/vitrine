// Private UIKit the SDK does not declare.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// The first matching method declared on this class, never an inherited method.
static inline Method SGOwnMethod(Class cls, SEL selector) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    Method own = NULL;
    for (unsigned int i = 0; i < count && !own; i++) {
        if (method_getName(methods[i]) == selector) own = methods[i];
    }
    free(methods);
    return own;
}

@interface UIView (SGPrivate)
- (NSString *)recursiveDescription;
@end

@interface UIViewController (SGPrivate)
- (NSString *)_printHierarchy;
@end
