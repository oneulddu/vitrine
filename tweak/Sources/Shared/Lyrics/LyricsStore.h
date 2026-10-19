// Offline lyrics, independent of UIKit. All file work is serialized on a utility queue;
// completions arrive on main. The codec does no I/O and may be used on either queue.
#import <Foundation/Foundation.h>
@class SGKaraokeLine;

NSDictionary *SGLyricsStoreEncode(NSArray<SGKaraokeLine *> *lines, NSString *credit);
NSArray<SGKaraokeLine *> *SGLyricsStoreDecode(id record, NSString **credit);
void SGLyricsStoreSave(NSString *track, NSArray<SGKaraokeLine *> *lines, NSString *credit);
void SGLyricsStoreLoad(NSString *track, void (^done)(NSArray<SGKaraokeLine *> *lines, NSString *credit));
void SGLyricsStoreDelete(NSString *track);
void SGLyricsStoreSize(void (^done)(unsigned long long bytes));
void SGLyricsStoreDeleteAll(void (^done)(unsigned long long remainingBytes));

// For tests only: enqueue an isolated directory and caps, with pruning unthrottled.
// Call before any test operations. Nothing touches the real store in that case.
void SGLyricsStoreConfigureForTests(NSURL *directory, NSUInteger countCap, unsigned long long byteCap);
