#import <Foundation/Foundation.h>

#define SGKeyLocalFileSuggest @"spotifyglass.localfiles.suggest"

extern const NSUInteger SGLocalInfoJSONLimit;
extern const NSUInteger SGLocalInfoCoverLimit;

NSString *SGLocalInfoQuery(NSString *title, NSString *artist, NSString *filename);
NSURL *SGLocalInfoSearchURL(NSString *query, NSString *region);
NSString *SGLocalInfoArtworkURL(NSString *url);
// nil denotes malformed/oversized JSON; an empty array is a valid answer with no usable songs.
NSArray<NSDictionary *> *SGLocalInfoParse(NSData *data);
// Lexicographic score: title token Jaccard, artist token Jaccard, then duration distance.
NSArray<NSDictionary *> *SGLocalInfoRank(NSArray<NSDictionary *> *songs, NSString *title,
                                        NSString *artist, NSTimeInterval seconds);

// One bounded, cookie-free transfer at a time. Main-thread API; completion arrives on main.
// Search parses off main and keeps at most 32 successful exact-request results in memory.
// Cancellation suppresses completion. Artwork is never cached here.
@interface SGLocalInfoLookup : NSObject <NSURLSessionDataDelegate>
@property(nonatomic, readonly) BOOL busy;
- (void)search:(NSURL *)url completion:(void (^)(NSArray<NSDictionary *> *, NSError *))completion;
- (void)cover:(NSURL *)url completion:(void (^)(NSData *, NSError *))completion;
- (void)cancel;
@end
