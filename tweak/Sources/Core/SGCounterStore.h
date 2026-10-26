#import <Foundation/Foundation.h>

// Thread-safe counters, lazily loaded from standard defaults. The feature prepares its loaded
// dictionary under the store's lock and returns YES only when that preparation needs persistence.
// Writes run on main, outside the lock, at most once per 30-second counting window or on flush.
@interface SGCounterStore : NSObject
- (instancetype)initWithKey:(NSString *)key prepare:(BOOL (^)(NSMutableDictionary<NSString *, NSNumber *> *counts))prepare;
- (NSDictionary<NSString *, NSNumber *> *)counts;
- (void)increment:(NSString *)label;
// Reset does not load old counts or cancel a pending timer. It flushes the empty current state.
- (void)reset;
// Synchronous on main, asynchronous otherwise; the snapshot is taken when the write runs.
- (void)flush;
@end
