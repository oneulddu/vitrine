// The AutoMix page's preview card (AutoMixSettings.m): what a change of song sounds like under the page's own rows,
// drawn as two curves over a beat grid, the outgoing song falling and the incoming one rising, with a title and a
// subtitle that say it in words. It reads the rows through the page and never writes a setting.
//
// The page also holds three options for the redesigned player (Redesigned/Player/PlayerMix.x reads them), here so
// either side can name them: Shared never imports the redesign.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

// Each off until switched on; shown on the page while AutoMix is on, and read by the redesigned player only.
#define SGKeyAutoMixShowProgress @"spotifyglass.automix.show-progress"
#define SGKeyAutoMixShowQueue @"spotifyglass.automix.show-queue"
#define SGKeyAutoMixArtwork @"spotifyglass.automix.artwork"
// Posted on the main thread, object nil, after the page stored one of the three.
extern NSNotificationName const SGAutoMixPlayerOptionsDidChangeNotification;

typedef NS_ENUM(NSInteger, SGAutoMixPreviewStyle) {
    SGAutoMixPreviewOff,           // the switch off: every song plays to its end, no overlap
    SGAutoMixPreviewBeatMatched,   // Spotify's Automix: the two curves step on the beats
    SGAutoMixPreviewCrossfade,     // a plain fade, the same length out and in
};

typedef struct {
    SGAutoMixPreviewStyle style;
    NSInteger seconds;   // Blend length as the page's slider reads it, 1 to 12
} SGAutoMixPreviewReading;

@interface SGAutoMixPreview : UIView
// `read` is asked for the rows' values at every reload.
- (instancetype)initWithReading:(SGAutoMixPreviewReading (^)(void))read;
// Reads the rows again; a change is drawn with a short fade unless Reduce Motion is on.
- (void)reload;
- (CGFloat)heightForWidth:(CGFloat)width;
@end
