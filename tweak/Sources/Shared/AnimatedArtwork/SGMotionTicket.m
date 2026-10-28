#import "SGMotionTicket.h"

@implementation SGMotionTicket
- (void)cancel {
    if (_cancelled) return;
    _cancelled = YES;
    [_child cancel];
    _child = nil;
    dispatch_block_t cancel = _onCancel;
    _onCancel = nil;
    if (cancel) cancel();
}
@end
