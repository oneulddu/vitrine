#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>

#define SGKeyPiPLayout @"spotifyglass.lyrics.pip.layout"
#define SGKeyPiPInfo @"spotifyglass.lyrics.pip.info"
#define SGKeyPiPAlignment @"spotifyglass.lyrics.pip.alignment"
#define SGKeyPiPFont @"spotifyglass.lyrics.pip.font"

// Raster points, not screen points. All roles are fitted again inside their own boxes.
@interface SGLyricsPiPStyle : NSObject
@property (nonatomic) NSInteger layout, alignment;
@property (nonatomic) BOOL info;
@property (nonatomic, copy) NSString *font;
@property (nonatomic, copy) NSArray<NSNumber *> *sizes, *weights;
@property (nonatomic, readonly) CGSize raster;
@property (nonatomic, readonly) NSArray *identity;
@end
SGLyricsPiPStyle *SGLyricsPiPReadStyle(void);
NSString *SGLyricsPiPRoleKey(NSUInteger role, NSString *field);
void SGLyricsPiPResetStyle(void);
// Stable identifiers, not indexes into a device-dependent font list. Never writes the app font.
// Every font the PiP can offer, and whether it can be drawn now: an imported or downloaded family only once it is
// registered (FontLibrary.h, Fonts.h), which the caller asks for and learns of by SGFontLibraryChangedNotification.
// Both read caches; neither registers anything.
NSArray<NSString *> *SGLyricsPiPFontCandidates(void);
BOOL SGLyricsPiPFontAvailable(NSString *identifier);
NSString *SGLyricsPiPFontName(NSString *identifier);
CTFontRef SGLyricsPiPCreateFont(SGLyricsPiPStyle *style, NSUInteger role, CGFloat size) CF_RETURNS_RETAINED;
