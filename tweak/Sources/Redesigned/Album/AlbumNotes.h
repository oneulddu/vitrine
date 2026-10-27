#import <UIKit/UIKit.h>

#define SGRKeyAlbumNotesPlace @"spotifyglass.redesign.album.notesPlace"
typedef NS_ENUM(NSInteger, SGRAlbumNotesPlace) {
    SGRAlbumNotesUnderPlay,
    SGRAlbumNotesUnderTracks,
    SGRAlbumNotesOff,
};
SGRAlbumNotesPlace SGRAlbumNotesWhere(void);

// AlbumHeader owns identity and the header's place in Spotify's stack.
void SGRAlbumNotesUpdate(UIView *header, UIView *page, NSString *artist, NSString *album);
// Observe only this cell. Tracks are remembered by index path and title within
// one collection snapshot; identical evidence does not recompute anything.
void SGRAlbumNotesObserveCell(UICollectionViewCell *cell);
// AlbumSections' collection hooks. Counts are checked once per list layout, not
// once per cell. Only observed track sections participate. Reloads and targeted
// track mutations invalidate same-count snapshots; unrelated batches do not.
// Hooks test this association before doing any album work or wrapping completion.
extern char SGRAlbumNotesCollectionOwnerKey;
void SGRAlbumNotesObserveSnapshot(UICollectionView *list);
void SGRAlbumNotesWillChangeSnapshot(UICollectionView *list);
void SGRAlbumNotesDidChangeSnapshot(UICollectionView *list);
void SGRAlbumNotesWillReload(UICollectionView *list);
void SGRAlbumNotesWillChangeItems(UICollectionView *list, NSArray<NSIndexPath *> *paths);
void SGRAlbumNotesWillChangeSections(UICollectionView *list, NSIndexSet *sections, BOOL shiftsFollowing);
// The last computed evidence, without walking views.
NSDictionary *SGRAlbumNotesEdition(UIView *page);
// AlbumSections owns the copyright cell and its extra lead, never the track list's data source.
CGFloat SGRAlbumNotesFooterHeight(UICollectionViewCell *cell, CGFloat width);
void SGRAlbumNotesLayoutFooter(UICollectionViewCell *cell);
void SGRAlbumNotesForgetFooter(UICollectionViewCell *cell);
void SGRAlbumNotesChanged(UIView *page);

@interface SGRAlbumNoteView : UIControl
@property (nonatomic, copy) NSDictionary *notes;
- (CGFloat)heightForWidth:(CGFloat)width;
@end
