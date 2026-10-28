#import "AnimatedArtwork.h"

// Internal request-chain ownership; all access is on main.
@interface SGMotionTicket ()
@property (nonatomic, readonly) BOOL cancelled;
@property (nonatomic, strong) SGMotionTicket *child;
@property (nonatomic, copy) dispatch_block_t onCancel;
@end
