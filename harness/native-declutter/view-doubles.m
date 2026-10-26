#import <UIKit/UIKit.h>

@implementation UIView
- (void)layoutIfNeeded {}
- (void)insertSubview:(UIView *)view atIndex:(NSInteger)index {
    [view removeFromSuperview];
    NSMutableArray *children = [self.subviews mutableCopy] ?: [NSMutableArray array];
    [children insertObject:view atIndex:(NSUInteger)index];
    self.subviews = children;
    view.superview = self;
}
- (void)removeFromSuperview {
    NSMutableArray *children = [self.superview.subviews mutableCopy];
    [children removeObjectIdenticalTo:self];
    self.superview.subviews = children;
    self.superview = nil;
}
@end
