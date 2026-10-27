// Imported lyrics files, on the Lyrics page beside the sources: the files kept (a swipe deletes one),
// Import for current track…, which links the file to the local file playing, Paste, which keeps the
// clipboard's lyrics for it, and Import lyrics…, matched by title and artist. Import opens Files and
// copies the file in; what it holds, TTML, LRC or plain text, is decided by its content.
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Player/PlayerState.h"
#import "LocalFiles.h"
#import "LocalLyrics.h"

typedef NS_ENUM(NSInteger, SGLRCImportRow) {
    SGLRCImportForTrack,
    SGLRCImportPasted,
    SGLRCImportByName,
    SGLRCImportRowCount,
};

// The local file playing, nil for anything else.
static NSString *playingLocalFile(void) {
    NSString *uri = SGURIString(SGPlayerState().track.URI);
    return SGLocalFileIs(uri) ? uri : nil;
}

// Why an import was refused, as its own words: the code says it, so every page says it the same.
static NSString *refusalText(NSError *error) {
    switch (error.code) {
        case SGLyricsImportErrorNothing:
            return SGL(@"settings.locallyrics.error.nothing", @"There is nothing to import.");
        case SGLyricsImportErrorTooLarge:
            return SGL(@"settings.locallyrics.error.toolarge", @"The lyrics are larger than 1 MB.");
        case SGLyricsImportErrorUnreadableFile:
            return SGL(@"settings.locallyrics.error.unreadablefile", @"The file could not be read.");
        case SGLyricsImportErrorStorage:
            return SGL(@"settings.locallyrics.error.storage", @"The lyrics could not be saved. The ones it had are unchanged.");
        default:
            return SGL(@"settings.locallyrics.error.unreadable", @"The lyrics could not be read as text.");
    }
}

@interface SGImportedLRCFilesPage : SGPage <UIDocumentPickerDelegate>
@end

@implementation SGImportedLRCFilesPage {
    NSArray<NSString *> *_files;
    UIView *_footer;
    // The local file playing when Paste or Files opened, nil for Import lyrics….
    NSString *_linkTo;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = SGL(@"settings.locallyrics.title", @"Imported lyrics files");
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _footer = SGNote(SGL(@"settings.locallyrics.footer", @"Import for current track links the file to the local file playing, whatever its tags say. "
                      "Paste keeps the clipboard's lyrics for it. Import lyrics… keeps a file for any track whose title and artist "
                      "match its [ti:] and [ar:] tags, or its name as \"Artist - Title\". A file may be TTML, LRC or plain text: "
                      "what it holds is read from its content. Swipe left on a file to delete it."));
    self.tableView.tableFooterView = _footer;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _footer, 16, 24);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _files = SGImportedLRCFiles();
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return 2;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? MAX((NSInteger)_files.count, 1) : SGLRCImportRowCount;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    return section == 0 ? SGSectionHeader(table, SGL(@"settings.locallyrics.files.header", @"Files")) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return section == 0 ? SGSectionHeaderHeight() : SGSectionGap;
}

- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section {
    return nil;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 1) {
        UITableViewCell *cell = SGDequeueCell(table, @"import");
        if (path.row == SGLRCImportByName) {
            SGFillCell(cell, SGL(@"settings.locallyrics.importbyname.title", @"Import lyrics…"), SGL(@"settings.locallyrics.importbyname.subtitle", @"Matched by title and artist"), nil, @"square.and.arrow.down");
        } else if (path.row == SGLRCImportPasted) {
            NSString *uri = playingLocalFile();
            SGFillCell(cell, SGL(@"settings.locallyrics.paste.title", @"Paste"),
                       uri ? SGLocalFileInfo(uri)[@"title"] : SGL(@"settings.locallyrics.importfortrack.notplaying", @"Start playing a local track first"),
                       uri ? nil : SGGrey(), @"doc.on.clipboard");
        } else {
            NSString *uri = playingLocalFile();
            NSString *title = SGLocalFileInfo(uri)[@"title"] ?: SGL(@"settings.locallyrics.importfortrack.defaulttitle", @"The local file playing");
            SGFillCell(cell, SGL(@"settings.locallyrics.importfortrack.title", @"Import for current track…"), uri ? title : SGL(@"settings.locallyrics.importfortrack.notplaying", @"Start playing a local track first"),
                       uri ? nil : SGGrey(), @"music.note");
        }
        BOOL enabled = path.row == SGLRCImportByName || playingLocalFile();
        cell.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        cell.accessibilityTraits = enabled ? UIAccessibilityTraitButton : UIAccessibilityTraitButton | UIAccessibilityTraitNotEnabled;
        return cell;
    }
    UITableViewCell *cell = SGDequeueCell(table, @"file");
    if (!_files.count) {
        SGFillCell(cell, SGL(@"settings.locallyrics.files.empty", @"No imported files"), nil, SGGrey(), nil);
        return cell;
    }
    SGFillCell(cell, _files[(NSUInteger)path.row], nil, nil, nil);
    return cell;
}

- (BOOL)tableView:(UITableView *)table shouldHighlightRowAtIndexPath:(NSIndexPath *)path {
    return path.section == 1 && (path.row == SGLRCImportByName || playingLocalFile());
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section != 1) return;
    _linkTo = path.row == SGLRCImportByName ? nil : playingLocalFile();
    if (!_linkTo && path.row != SGLRCImportByName) return;
    if (path.row == SGLRCImportPasted) {
        [self pasteInto:_linkTo];
        return;
    }
    // No lyrics kind is a registered type, so Files offers any file and its content is read after.
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

// Read only once the row is tapped: the page itself never touches the clipboard, and an empty one says
// so instead of importing nothing.
- (void)pasteInto:(NSString *)uri {
    NSString *text = UIPasteboard.generalPasteboard.string;
    if (!text.length) {
        SGPresentInformation(self, SGL(@"settings.locallyrics.error.nothing.title", @"Nothing to import"), refusalText([NSError errorWithDomain:SGLyricsImportErrorDomain code:SGLyricsImportErrorNothing userInfo:nil]));
        return;
    }
    SGImportPastedLyrics(text, uri, ^(NSString *name, NSError *error) {
        if (!name) {
            BOOL nothing = error.code == SGLyricsImportErrorNothing;
            SGPresentInformation(self, nothing ? SGL(@"settings.locallyrics.error.nothing.title", @"Nothing to import")
                                               : SGL(@"settings.locallyrics.error.pastefailed", @"Could not import the lyrics"), refusalText(error));
            return;
        }
        [self reloadFiles];
        [self sayLinked:name to:uri];
    });
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)table trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section != 0 || !_files.count) return nil;
    NSString *name = _files[(NSUInteger)path.row];
    // The store answers on the main queue once the file is gone, which is when the row goes and the
    // swipe's own completion can be told.
    __weak typeof(self) weakSelf = self;
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:SGL(@"common.delete", @"Delete")
        handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
            SGDeleteImportedLRC(name, ^(BOOL deleted) {
                SGImportedLRCFilesPage *page = weakSelf;
                if (deleted) [page reloadFiles];
                else if (page) SGPresentInformation(page, SGL(@"settings.locallyrics.error.deletefailed", @"Could not delete the file"), nil);
                done(deleted);
            });
        }];
    delete.image = [UIImage systemImageNamed:@"trash"];
    return [UISwipeActionsConfiguration configurationWithActions:@[delete]];
}

- (void)reloadFiles {
    _files = SGImportedLRCFiles();
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationFade];
}

// Says what the file now gives, for a file linked to the local file playing.
- (void)sayLinked:(NSString *)name to:(NSString *)uri {
    if (!uri) return;
    NSString *title = SGLocalFileInfo(uri)[@"title"];
    SGPresentInformation(self, SGL(@"settings.locallyrics.linked.title", @"Lyrics linked"), [NSString stringWithFormat:SGL(@"settings.locallyrics.linked.message", @"%@ now gives the lyrics for %@."), name,
                                                                 title ? [NSString stringWithFormat:@"\"%@\"", title] : SGL(@"settings.locallyrics.linked.thislocalfile", @"this local file")]);
}

- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    NSString *linkTo = _linkTo;
    SGImportLRC(url, linkTo, ^(NSString *name, NSError *error) {
        if (!name) {
            SGPresentInformation(self, SGL(@"settings.locallyrics.error.importfailed", @"Could not import the file"), refusalText(error));
            return;
        }
        [self reloadFiles];
        [self sayLinked:name to:linkTo];
    });
}

@end

UIViewController *SGImportedLRCPage(void) {
    return [SGImportedLRCFilesPage new];
}
