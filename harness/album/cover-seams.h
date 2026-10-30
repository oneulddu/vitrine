// External boundaries controlled by cover-hero-check.m; injected into generated AlbumHeader.m only.
#import <UIKit/UIKit.h>
@class AVPlayer, AVPlayerLayer, SGRCoverReading;

void SGRAlbumTestAlbumCover(NSString *artist, NSString *album, CGFloat pixels, void (^done)(NSURL *));
void SGRAlbumTestPoster(NSURL *file, void (^done)(UIImage *));
BOOL SGRAlbumTestStillRead(UIImage *image, void (^done)(SGRCoverReading *));
AVPlayerLayer *SGRAlbumTestPlayerLayer(AVPlayer *player);
NSCache *SGRAlbumTestRenderCache(void);
