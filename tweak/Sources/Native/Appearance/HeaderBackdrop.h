// Native album and playlist headers keep their own association namespaces and discovery.
#import "Core/SGBackdrop.h"
#import <objc/runtime.h>

static inline void SGNativeHeaderBackdrop(UIView *header, UIImage *image, const void *backdropKey, const void *sourceKey) {
    UIView *backdrop = objc_getAssociatedObject(header, backdropKey);
    if (!backdrop) {
        backdrop = SGBackdropMake(header.bounds, 1);
        objc_setAssociatedObject(header, backdropKey, backdrop, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (backdrop.superview != header) [header insertSubview:backdrop atIndex:1];
    UIImageView *sample = SGBackdropImageView(backdrop);
    if (objc_getAssociatedObject(sample, sourceKey) == image) return;
    objc_setAssociatedObject(sample, sourceKey, image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    sample.image = SGBackdropSample(image);
}
