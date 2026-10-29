#import <UIKit/UIKit.h>

// Review owns selection and the on-demand cover transfer, never persistence.
@interface SGLocalInfoReview : UITableViewController
- (instancetype)initWithSongs:(NSArray<NSDictionary *> *)songs current:(NSDictionary *)current
                       cover:(UIImage *)cover durationUnknown:(BOOL)unknown
                      accept:(void (^)(NSDictionary<NSString *, NSString *> *, UIImage *))accept;
@end
