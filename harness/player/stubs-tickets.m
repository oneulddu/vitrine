// MotionSources.m's cancellable walk, for sources whose animated artwork store hands out tickets (SGMotionTicket.m);
// build.sh compiles this only where that file exists. Its delayed lookup uses the production ticket's cancellation
// contract; a cancelled consumer is not called when the shared lookup finishes.
#import "Shared/AnimatedArtwork/SGMotionTicket.h"

SGMotionTicket *SGMotionRequestClip(NSString *uri, NSURL *canvas, NSString *artist, NSString *album, CGFloat pixels,
                                   void (^done)(NSURL *file, NSString *source)) {
    SGMotionTicket *ticket = [SGMotionTicket new];
    SGMotionClipFor(uri, canvas, artist, album, pixels, ^(NSURL *file, NSString *source) {
        if (!ticket.cancelled) done(file, source);
    });
    return ticket;
}
