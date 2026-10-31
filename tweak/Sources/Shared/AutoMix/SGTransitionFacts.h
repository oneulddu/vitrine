#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SGTransitionKind) {
    SGTransitionKindNone,
    SGTransitionKindCrossfade,
    SGTransitionKindSpotifyAutomix,
};

// Immutable, playing -> first future item only. UID distinguishes repeated queue entries.
@interface SGTransitionFacts : NSObject
@property (nonatomic, copy, readonly) NSString *fromURI;
@property (nonatomic, copy, readonly, nullable) NSString *fromUID;
@property (nonatomic, copy, readonly) NSString *toURI;
@property (nonatomic, copy, readonly, nullable) NSString *toUID;
@property (nonatomic, readonly) SGTransitionKind kind;
// Seconds in each recording, not the player's shortened transition clock.
// All four are zero when timesKnown is NO; do not draw a window in that case.
@property (nonatomic, readonly) BOOL timesKnown;
@property (nonatomic, readonly) NSTimeInterval outStart;
@property (nonatomic, readonly) NSTimeInterval outEnd;
@property (nonatomic, readonly) NSTimeInterval inStart;
@property (nonatomic, readonly) NSTimeInterval inEnd;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

// Main thread. Cached; nil means no proven upcoming blend, including unknown/locality not yet known.
FOUNDATION_EXPORT SGTransitionFacts * _Nullable SGAutoMixCurrentTransition(void);
// Main thread, object/userInfo nil. Posted only when the public facts change, including to/from nil.
FOUNDATION_EXPORT NSNotificationName const SGAutoMixTransitionDidChangeNotification;

NS_ASSUME_NONNULL_END
