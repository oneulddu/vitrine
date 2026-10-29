// The Visualizer's Poster and Cut styles (PlayerLyricStages.m): the sung line drawn over the field, handed to
// them by PlayerVisualiser.m's view, which reads the lines and the clock and names the line as for Lyrics. A stage
// compares the line and word it is handed with the ones it shows and builds text only when they change; on the
// frame clock it only counts the line's started words. With no line (-1) it fades away, leaving the view's quiet
// hills. Main thread only.
#import <UIKit/UIKit.h>

@class SGKaraokeLine;

@interface SGRLyricStage : UIView
// The stage for a style id, nil for a style without one.
+ (SGRLyricStage *)stageForStyle:(NSString *)identifier;
// Whether a line shows: in the player the cover gives the field up to the type meanwhile (PlayerVisualiser.m).
@property (nonatomic, readonly) BOOL showing;
// Where the type sets, in the stage's coordinates: the visible field within the player's margins, and the
// height its type is centered on; `elsewhere` when the player shows the sung line itself, which the type then
// does not repeat.
- (void)setField:(CGRect)field centre:(CGFloat)centre lineElsewhere:(BOOL)elsewhere;
// The playing track's own cover and its identity (SGRNowPlayingArtwork), both nil while it has none.
- (void)setCover:(UIImage *)cover identity:(NSString *)identity;
// The cover's five flow colors (SGRPalette), as the view's hills read them.
- (void)setColours:(NSArray<UIColor *> *)colours;
// Shows line `index` of `lines` at `ms`, -1 for none. A line is told apart by the line itself, not its index, so
// lines replaced under the same index are set again.
- (void)showLine:(NSInteger)index of:(NSArray<SGKaraokeLine *> *)lines at:(NSInteger)ms;
@end
