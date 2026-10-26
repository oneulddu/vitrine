// Foundation-only view doubles for the native classification helper, not a UIKit renderer.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface UIView : NSObject
@property (nonatomic, copy) NSArray<UIView *> *subviews;
@property (nonatomic) CGRect bounds;
@property (nonatomic, weak) UIView *superview;
- (void)insertSubview:(UIView *)view atIndex:(NSInteger)index;
- (void)removeFromSuperview;
- (void)layoutIfNeeded;
@end
@interface UIImage : NSObject
@end
@interface UIImageView : UIView
@property (nonatomic, strong) UIImage *image;
@end
@interface UICollectionView : UIView
@property (nonatomic, copy) void (^layout)(void);
@end
@class UIStackView, UITableView, UIColor;

@interface NSIndexPath (NativeDeclutterUIKit)
@property (nonatomic, readonly) NSInteger item;
@property (nonatomic, readonly) NSInteger section;
+ (instancetype)indexPathForItem:(NSInteger)item inSection:(NSInteger)section;
@end
