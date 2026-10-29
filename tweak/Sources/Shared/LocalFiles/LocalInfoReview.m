#import "LocalInfoReview.h"
#import "LocalInfoLookup.h"
#import "LocalFiles.h"
#import "Core/SGCore.h"

@implementation SGLocalInfoReview {
    NSArray<NSDictionary *> *_songs;
    NSDictionary *_current;
    UIImage *_currentCover;
    NSUInteger _selected;
    NSMutableSet<NSString *> *_checked;
    BOOL _unknown;
    SGLocalInfoLookup *_lookup;
    void (^_accept)(NSDictionary *, UIImage *);
    NSUInteger _generation;
}

static NSArray *reviewFields(void) { return @[@"title", @"artist", @"album", @"cover"]; }
static NSArray *reviewLabels(void) {
    return @[SGL(@"settings.edit_info.field.title", @"Title"), SGL(@"settings.edit_info.field.artist", @"Artist"),
             SGL(@"settings.edit_info.field.album", @"Album"), SGL(@"settings.album.cover.header", @"Cover")];
}

- (instancetype)initWithSongs:(NSArray<NSDictionary *> *)songs current:(NSDictionary *)current
                       cover:(UIImage *)cover durationUnknown:(BOOL)unknown
                      accept:(void (^)(NSDictionary<NSString *, NSString *> *, UIImage *))accept {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    _songs = songs;
    _current = current;
    _currentCover = cover;
    _unknown = unknown;
    _accept = [accept copy];
    _lookup = [SGLocalInfoLookup new];
    _checked = [NSMutableSet set];
    for (NSString *key in reviewFields()) if ([self differs:key song:songs[0]]) [_checked addObject:key];
    self.title = SGL(@"settings.edit_info.suggest.title", @"Find Info");
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:SGL(@"settings.edit_info.suggest.reject", @"Not This Song") style:UIBarButtonItemStylePlain
        target:self action:@selector(reject)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:SGL(@"settings.edit_info.suggest.use", @"Use") style:UIBarButtonItemStyleDone
        target:self action:@selector(use)];
    return self;
}

- (BOOL)differs:(NSString *)key song:(NSDictionary *)song {
    // A remote cover has no identity in the local overlay. Never fetch it merely to compare pixels.
    return [song[key] length] && ([key isEqual:@"cover"] || ![song[key] isEqual:_current[key] ?: @""]);
}

- (void)reject {
    ++_generation;
    [_lookup cancel];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.isBeingDismissed || self.navigationController.isBeingDismissed || !self.view.window) {
        ++_generation;
        [_lookup cancel];
    }
}

- (void)dealloc { [_lookup cancel]; }

- (void)apply:(UIImage *)cover {
    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"title", @"artist", @"album"])
        if ([_checked containsObject:key]) names[key] = _songs[_selected][key];
    _accept(names, cover);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)use {
    if (!self.navigationItem.rightBarButtonItem.enabled) return;
    if (![_checked containsObject:@"cover"]) { [self apply:nil]; return; }
    self.navigationItem.rightBarButtonItem.enabled = NO;
    self.tableView.userInteractionEnabled = NO;
    NSUInteger generation = ++_generation;
    __weak typeof(self) weakSelf = self;
    [_lookup cover:[NSURL URLWithString:_songs[_selected][@"cover"]]
        completion:^(NSData *data, NSError *error) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            UIImage *image = data ? SGLocalFileReadCoverData(data) : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                SGLocalInfoReview *self = weakSelf;
                if (!self || generation != self->_generation) return;
                self.navigationItem.rightBarButtonItem.enabled = YES;
                self.tableView.userInteractionEnabled = YES;
                if (image) { [self apply:image]; return; }
                NSString *message = [error.userInfo[NSURLErrorNetworkUnavailableReasonKey] integerValue] == NSURLErrorNetworkUnavailableReasonConstrained ?
                    SGL(@"settings.edit_info.suggest.low_data", @"Find Info is unavailable in Low Data Mode.") :
                    SGL(@"settings.edit_info.suggest.cover_error", @"The cover could not be loaded. Try again or uncheck Cover.");
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.ok", @"OK") style:UIAlertActionStyleDefault handler:nil]];
                SGPresentDark(alert);
                [self presentViewController:alert animated:YES completion:nil];
            });
        });
    }];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 5 : (NSInteger)_songs.count - 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? nil : SGL(@"settings.edit_info.suggest.other", @"Other Matches");
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != 0) return nil;
    NSString *privacy = SGL(@"settings.edit_info.suggest.privacy", @"The song's name is sent to Apple's iTunes Search.");
    NSString *cover = SGL(@"settings.edit_info.suggest.cover_note", @"The suggested cover downloads only when you tap Use with Cover checked.");
    return [NSString stringWithFormat:@"%@\n%@%@", cover, privacy, _unknown ?
        [@"\n" stringByAppendingString:SGL(@"settings.edit_info.suggest.unknown_duration", @"This file's length is unknown. Matches are not filtered by duration.")] : @""];
}
- (NSUInteger)songIndexForRow:(NSInteger)row { return (NSUInteger)row < _selected ? (NSUInteger)row : (NSUInteger)row + 1; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.textProperties.numberOfLines = 0;
    content.secondaryTextProperties.numberOfLines = 0;
    NSDictionary *song = _songs[_selected];
    if (path.section == 1) {
        song = _songs[[self songIndexForRow:path.row]];
        content.text = song[@"title"];
        content.secondaryText = [NSString stringWithFormat:@"%@ · %@ · %@", song[@"artist"], song[@"album"], song[@"year"]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (path.row == 4) {
        content.text = SGL(@"settings.edit_info.suggest.year", @"Year");
        content.secondaryText = [song[@"year"] length] ? song[@"year"] : SGL(@"settings.edit_info.suggest.unknown", @"Unknown");
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        NSString *key = reviewFields()[path.row];
        content.text = reviewLabels()[path.row];
        NSString *current = _current[key] ?: @"";
        NSString *suggested = song[key];
        if ([key isEqual:@"cover"]) {
            content.image = _currentCover ?: [UIImage systemImageNamed:@"music.note"];
            content.imageProperties.maximumSize = CGSizeMake(56, 56);
            current = _currentCover ? SGL(@"settings.edit_info.cover.your_picture", @"Your picture") :
                SGL(@"settings.edit_info.cover.file_own", @"The file's own");
            suggested = [suggested length] ? SGL(@"settings.edit_info.suggest.cover_available", @"New cover available") :
                SGL(@"settings.edit_info.suggest.unknown", @"Unknown");
        }
        content.secondaryText = [NSString stringWithFormat:SGL(@"settings.edit_info.suggest.comparison", @"Current: %@\nSuggested: %@"), current, suggested];
        BOOL enabled = [self differs:key song:song];
        cell.accessoryType = [_checked containsObject:key] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        cell.accessibilityTraits = UIAccessibilityTraitButton | ([_checked containsObject:key] ? UIAccessibilityTraitSelected : 0) |
            (enabled ? 0 : UIAccessibilityTraitNotEnabled);
        content.textProperties.color = enabled ? UIColor.labelColor : UIColor.secondaryLabelColor;
    }
    cell.contentConfiguration = content;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == 1) {
        NSDictionary *old = _songs[_selected];
        _selected = [self songIndexForRow:path.row];
        for (NSString *key in reviewFields()) {
            if (![self differs:key song:_songs[_selected]]) [_checked removeObject:key];
            else if (![self differs:key song:old]) [_checked addObject:key];
        }
    } else if (path.row < 4) {
        NSString *key = reviewFields()[path.row];
        if ([self differs:key song:_songs[_selected]]) {
            if ([_checked containsObject:key]) [_checked removeObject:key];
            else [_checked addObject:key];
        }
    }
    [tableView reloadData];
}
@end
