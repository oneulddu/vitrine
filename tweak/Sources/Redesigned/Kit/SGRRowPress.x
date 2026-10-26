// The Music app's highlight under the finger on the track rows of Element_List's lists: an album's tracks
// (Album/AlbumRows.x styles them) and every other list built of the same retrieval rows, an artist's popular
// tracks among them. The playlist's rows are another cell class and get theirs from Playlist/PlaylistRows.x.
//
// Tree (trees/clean/album/03.txt:524-575, as AlbumRows.x reads it): an Element_List.CollectionViewCell whose
// content is a RetrievalListStructuredData view holding an Encore.ListRow, id=Components.UI.RetrievalRow*.
// The same cell class carries Home's sections and the album's footer, which keep no highlight.
#import "Core/SGCore.h"
#import "SGRedesign.h"
#import "SGRRestyle.h"
#import "SGRPress.h"

static char kRetrievalRowKey;

%hook _TtC12Element_List18CollectionViewCell
- (void)layoutSubviews {
    %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    BOOL row = SGRIsTrackContent(cell.contentView.subviews.firstObject)
            && SGRFindByIdentifier(cell, @"Components.UI.RetrievalRow*", &kRetrievalRowKey) != nil;
    SGRPressRow(cell, row);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC12Element_List18CollectionViewCell"]);
}
