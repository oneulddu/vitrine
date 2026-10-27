#import <UIKit/UIKit.h>

// Loaded release rows, identified by their controls and dated subtitle, never
// by localized section headings. The request below retains their evidence.
NSArray<NSString *> *SGRArtistReleaseTitles(UIView *root);

// One page/hero owns one request state. The live identity is checked at delivery,
// not just when a new request starts (two artists can have exactly the same name).
@interface SGRArtistArtworkRequest : NSObject
// Cheap preflight before the header walks release rows. Missing identity never
// authorizes a presentation change. In-flight requests still collect evidence;
// only a completed current identity needs no scan.
- (BOOL)needsReleaseEvidenceForIdentity:(NSString *)identity;
// Deliver a result retained across a transient missing identity, without a scan
// or another asset attempt. A different identity never consumes that result.
- (void)applyPendingResultForIdentity:(NSString *)identity apply:(void (^)(UIImage *, NSURL *))apply;
- (void)updateIdentity:(NSString *)identity name:(NSString *)name titles:(NSArray<NSString *> *)titles
                 photo:(BOOL)photo motion:(BOOL)motion
       currentIdentity:(NSString *(^)(void))currentIdentity
                 apply:(void (^)(UIImage *, NSURL *))apply;
@end

@interface SGRArtistMotionView : UIView
- (void)showFile:(NSURL *)file;
@end
