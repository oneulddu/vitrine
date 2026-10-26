// Foundation-only view doubles for the native classification helper, not a UIKit renderer.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface UIView : NSObject
@property (nonatomic, copy) NSArray<UIView *> *subviews;
- (void)layoutIfNeeded;
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
