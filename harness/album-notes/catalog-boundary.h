// Replayed catalog-shaped fixtures, not claims about current Apple availability.
#import <UIKit/UIKit.h>
#define CHECK(value) do { if (!(value)) { fprintf(stderr, "FAIL %d: %s\n", __LINE__, #value); exit(1); } } while (0)
extern NSDictionary *CatalogFixture;
extern BOOL CatalogLowData;
extern NSInteger CatalogStatus;
extern NSUInteger CatalogSearches, CatalogAlbumRequests, CatalogMediaRequests, CatalogDownloads;
extern NSUInteger CatalogArtistRequests;
extern NSURL *CatalogRoot;
extern NSMutableArray<NSString *> *CatalogAssetPaths;
void CatalogStart(NSString *path);
void CatalogFinish(void);
void CatalogWait(BOOL (^ready)(void));
NSURL *SGMotionTestAlbumAnswersFile(void);
