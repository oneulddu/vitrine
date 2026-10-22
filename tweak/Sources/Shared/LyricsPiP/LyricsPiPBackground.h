// Main-thread coordinator. Fetches only the current URI's proven player artwork, and prepares
// backgrounds on a serial worker queue. A stopped session never publishes a pending result.
#import <UIKit/UIKit.h>

#define SGKeyLyricsPiPBackground @"spotifyglass.lyrics.pip.background"

@interface SGLyricsPiPBackground : NSObject
@property (nonatomic, readonly) UIImage *image;
@property (nonatomic, readonly) UIImage *cover;
@property (nonatomic, readonly) NSUInteger revision;
@property (nonatomic, copy) void (^changed)(void);
- (void)refreshForTrack:(NSString *)track;
- (void)invalidate;
@end
