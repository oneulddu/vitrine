// MotionSources.m's cancellable walk, for sources whose animated artwork store hands out tickets (SGMotionTicket.m);
// build.sh compiles this only where that file exists. The walk is stubs.m's SGMotionClipFor, and its ticket cancels
// nothing: the harness never cancels a walk.
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"

SGMotionTicket *SGMotionRequestClip(NSString *uri, NSURL *canvas, NSString *artist, NSString *album, CGFloat pixels,
                                   void (^done)(NSURL *file, NSString *source)) {
    SGMotionClipFor(uri, canvas, artist, album, pixels, done);
    return [SGMotionTicket new];
}
