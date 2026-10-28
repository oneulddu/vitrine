#import <Foundation/Foundation.h>
// The production transport's only dependency on Lyrics; this fixture never links UIKit.
void SGSpclientHeaders(void (^use)(NSDictionary<NSString *, NSString *> *headers));
