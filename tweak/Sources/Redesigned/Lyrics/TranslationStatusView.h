// The lyrics view's one-line note about automatic translation, beside the translate button: which service is
// working and how far it got, or how it ended with a Retry. Nothing here asks a translator anything: a tap only
// hands the track and language the note was drawn for back to `retry`.
#import <UIKit/UIKit.h>
#import "AutoTranslation.h"

@interface SGRTranslationStatusView : UIView
// Nil, or a Complete snapshot, hides the note. The track and language are the snapshot's own.
- (void)showProgress:(SGRAutoTranslationProgress *)progress track:(NSString *)track language:(NSString *)language;
@property (nonatomic, readonly) BOOL showsNote;
@property (nonatomic, copy) void (^retry)(NSString *track, NSString *language);
@end
