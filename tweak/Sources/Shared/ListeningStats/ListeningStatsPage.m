// Shared local history pages. The log is main-owned; parsing, export and aggregation use snapshots.
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "ListeningStats.h"
#import "SGPlayLog.h"

static BOOL sg_importing, sg_exporting, sg_picking;

@interface SGListeningPage : SGModPage
@property (nonatomic, copy) void (^refreshHistory)(void);
@property (nonatomic) NSUInteger generation;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL observing;
@end
@implementation SGListeningPage
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.observing) {
        self.observing = YES;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(historyChanged)
            name:SGPlayLogDidChangeNotification object:SGListeningLog()];
    }
    if (self.refreshHistory) self.refreshHistory();
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.observing) {
        [NSNotificationCenter.defaultCenter removeObserver:self name:SGPlayLogDidChangeNotification object:SGListeningLog()];
        self.observing = NO;
    }
}
- (void)historyChanged {
    if (self.refreshHistory) self.refreshHistory();
}
@end

static NSString *duration(int64_t ms) {
    if (ms > 0 && ms < 60000) return SGL(@"settings.stats.time.less_than_minute", @"<1 min");
    int64_t minutes = ms / 60000;
    if (minutes < 60) return [NSString stringWithFormat:SGL(@"settings.stats.time.minutes", @"%lld min"), minutes];
    return [NSString stringWithFormat:SGL(@"settings.stats.time.hours_minutes", @"%lld h %lld min"), minutes / 60, minutes % 60];
}
static NSString *playsText(NSUInteger plays) {
    return [NSString stringWithFormat:plays == 1 ? SGL(@"settings.stats.plays.singular", @"%lu play") : SGL(@"settings.stats.plays.plural", @"%lu plays"), (unsigned long)plays];
}
static NSString *daysText(NSUInteger days) {
    return [NSString stringWithFormat:days == 1 ? SGL(@"settings.stats.days.singular", @"%lu day") : SGL(@"settings.stats.days.plural", @"%lu days"), (unsigned long)days];
}
static void present(UIViewController *controller) {
    SGPresentDark(controller);
    [SGTopController() presentViewController:controller animated:YES completion:nil];
}
static void showAlert(NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.ok", @"OK") style:UIAlertActionStyleCancel handler:nil]];
    present(alert);
}
static SGModSection *topSection(NSString *title, NSArray<SGStatEntry *> *entries) {
    NSMutableArray<SGModRow *> *rows = [NSMutableArray array];
    [entries enumerateObjectsUsingBlock:^(SGStatEntry *entry, NSUInteger i, BOOL *stop) {
        NSString *plays = playsText(entry.plays);
        SGModRow *row = SGStatRow([NSString stringWithFormat:SGL(@"settings.stats.rank_format", @"%lu. %@"), (unsigned long)i + 1, entry.name], ^NSString *{ return plays; });
        row.subtitle = entry.detail;
        [rows addObject:row];
    }];
    if (!rows.count) [rows addObject:SGStatRow(SGL(@"settings.stats.empty", @"Nothing yet"), nil)];
    return SGSection(title, rows);
}
static UIViewController *hoursPage(NSArray<SGStatEntry *> *hours) {
    NSMutableArray *rows = [NSMutableArray array];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = NSLocale.currentLocale;
    // A non-DST day in UTC supplies every wall-clock hour; locale selects 12/24 h.
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    [formatter setLocalizedDateFormatFromTemplate:@"j"];
    for (NSUInteger hour = 0; hour < 24; hour++) {
        NSString *label = [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:hour * 3600]];
        SGStatEntry *entry = hours[hour];
        NSString *time = duration(entry.ms);
        SGModRow *row = SGStatRow(label, ^NSString *{ return time; });
        row.subtitle = playsText(entry.plays);
        [rows addObject:row];
    }
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.stats.hours.title", @"By hour of day")
        intro:SGL(@"settings.stats.hours.intro", @"Each play and its listening time count in the local hour when it ended. Repeated daylight-saving hours are combined.")
        sections:@[SGSection(nil, rows)] footer:nil];
}
static UIViewController *periodPage(NSString *title, int64_t since) {
    SGModSection *summary = SGSection(nil, @[SGStatRow(SGL(@"settings.stats.status.loading", @"Loading…"), nil)]);
    SGModSection *tracks = SGSection(SGL(@"settings.stats.section.top_tracks", @"Top tracks"), @[]), *artists = SGSection(SGL(@"settings.stats.section.top_artists", @"Top artists"), @[]), *albums = SGSection(SGL(@"settings.stats.section.top_albums", @"Top albums"), @[]);
    SGModPage *page = [[SGModPage alloc] initWithTitle:title intro:nil sections:@[summary, tracks, artists, albums] footer:nil];
    __weak SGModPage *weakPage = page;
    [SGListeningLog() loadWithCompletion:^{
        if (SGListeningLog().loadError) {
            SGModRow *error = SGStatRow(SGL(@"settings.stats.error.load", @"Could not load history"), nil);
            error.subtitle = SGListeningLog().loadError.localizedDescription;
            summary.rows = @[error];
            [weakPage refreshVisibility];
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, error.title);
            return;
        }
        NSArray *snapshot = [SGListeningLog().plays copy];
        NSCalendar *calendar = [NSCalendar.currentCalendar copy];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            SGStats *stats = SGStatsSince(snapshot, since, 25);
            NSArray *hours = SGHourlyStats(snapshot, since, calendar);
            dispatch_async(dispatch_get_main_queue(), ^{
                SGModPage *page = weakPage;
                if (!page) return;
                NSString *time = duration(stats.ms), *plays = playsText(stats.plays);
                summary.rows = @[
                    SGStatRow(SGL(@"settings.stats.row.listening_time", @"Listening time"), ^NSString *{ return time; }),
                    SGStatRow(SGL(@"settings.stats.row.plays", @"Plays"), ^NSString *{ return plays; }),
                    SGPageRow(SGL(@"settings.stats.row.by_hour", @"By hour of day"), ^UIViewController *{ return hoursPage(hours); })];
                tracks.rows = topSection(SGL(@"settings.stats.section.top_tracks", @"Top tracks"), stats.tracks).rows;
                artists.rows = topSection(SGL(@"settings.stats.section.top_artists", @"Top artists"), stats.artists).rows;
                albums.rows = topSection(SGL(@"settings.stats.section.top_albums", @"Top albums"), stats.albums).rows;
                [page refreshVisibility];
                [page.tableView reloadData];
                UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, stats.plays ? SGL(@"settings.stats.a11y.loaded", @"History loaded") : SGL(@"settings.stats.a11y.no_plays", @"No plays in this period"));
            });
        });
    }];
    return page;
}

#pragma mark - document picker

@interface SGHistoryPicker : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, weak) SGListeningPage *page;
@property (nonatomic, strong) NSURL *temporaryDirectory;
@end
@implementation SGHistoryPicker
- (void)finishExport {
    NSURL *directory = self.temporaryDirectory;
    self.temporaryDirectory = nil;
    sg_exporting = NO;
    [self.page.tableView reloadData];
    if (directory) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
    });
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    sg_picking = NO;
    if (self.temporaryDirectory) {
        [self finishExport];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, SGL(@"common.cancel", @"Cancel"));
    }
}
- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    sg_picking = NO;
    if (self.temporaryDirectory) {
        [self finishExport];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, SGL(@"settings.stats.a11y.exported", @"History exported"));
        return;
    }
    SGListeningPage *page = self.page;
    sg_importing = YES;
    [page.tableView reloadData];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, SGL(@"settings.stats.a11y.importing", @"Importing"));
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        SGHistoryImport *result = SGReadHistoryURLs(urls);
        dispatch_async(dispatch_get_main_queue(), ^{
            sg_importing = NO;
            if (!result.files) {
                [page.tableView reloadData];
                showAlert(SGL(@"settings.stats.alert.no_history_found.title", @"No listening history found"), SGL(@"settings.stats.alert.no_history_found.message", @"Choose a Vitrine history export, Spotify StreamingHistory_music or Streaming_History_Audio JSON files, their ZIP, or a folder containing JSON files. Unreadable, unsupported or oversized files are skipped."));
                return;
            }
            NSUInteger added = [SGListeningLog() merge:result.plays];
            showAlert(SGL(@"settings.stats.alert.imported.title", @"Imported"), [NSString stringWithFormat:SGL(@"settings.stats.alert.imported.message", @"%@ added from %lu files. %lu duplicate plays and %lu unreadable, unsupported or over-limit items skipped."),
                playsText(added), (unsigned long)result.files, (unsigned long)(result.plays.count - added), (unsigned long)result.skipped]);
        });
    });
}
@end
static SGHistoryPicker *historyPicker(void) {
    static SGHistoryPicker *delegate;
    if (!delegate) delegate = [SGHistoryPicker new];
    return delegate;
}
static BOOL busy(SGListeningPage *page) {
    return !page || page.loading || SGListeningLog().loadError || sg_importing || sg_exporting || sg_picking;
}
static void pickExport(SGListeningPage *page, BOOL folder) {
    if (busy(page)) return;
    sg_picking = YES;
    SGHistoryPicker *delegate = historyPicker();
    delegate.page = page;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:folder ? @[UTTypeFolder] : @[UTTypeJSON, UTTypeZIP] asCopy:NO];
    picker.allowsMultipleSelection = YES;
    picker.delegate = delegate;
    present(picker);
}
static void exportHistory(SGListeningPage *page) {
    if (busy(page)) return;
    NSArray *snapshot = [SGListeningLog().plays copy];
    if (!snapshot.count) { showAlert(SGL(@"settings.stats.alert.no_history_export.title", @"No history to export"), SGL(@"settings.stats.alert.no_history_export.message", @"Record or import some plays first.")); return; }
    sg_exporting = YES;
    [page.tableView reloadData];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, SGL(@"settings.stats.a11y.preparing_export", @"Preparing export"));
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error;
        NSData *data = SGHistoryJSON(snapshot, &error);
        NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        NSURL *url = [directory URLByAppendingPathComponent:@"Vitrine-listening-history.json"];
        BOOL saved = data && [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error]
                          && [data writeToURL:url options:NSDataWritingAtomic error:&error];
        if (!saved) [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!saved) {
                sg_exporting = NO;
                [page.tableView reloadData];
                showAlert(SGL(@"settings.stats.alert.export_failed.title", @"Could not export history"), error.localizedDescription ?: SGL(@"settings.stats.error.try_again", @"Please try again."));
                return;
            }
            SGHistoryPicker *delegate = historyPicker();
            delegate.page = page;
            delegate.temporaryDirectory = directory;
            UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[url] asCopy:YES];
            picker.delegate = delegate;
            present(picker);
        });
    });
}
static void confirmErase(SGListeningPage *page) {
    // Erase is also the recovery path for a damaged log, so loading and load errors must not disable it.
    if (!page || sg_importing || sg_exporting || sg_picking) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.stats.alert.erase.title", @"Erase listening history?")
        message:SGL(@"settings.stats.alert.erase.message", @"Every play recorded on this phone and every one imported is deleted. Spotify's own history is untouched.")
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.stats.alert.erase.action", @"Erase") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [SGListeningLog() erase];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    present(alert);
}

#pragma mark - summary

UIViewController *SGListeningStatsPage(void) {
    NSMutableDictionary<NSString *, NSString *> *values = [NSMutableDictionary dictionary];
    NSMutableArray *periods = [NSMutableArray array];
    NSArray *names = @[SGL(@"settings.stats.period.week", @"Past week"), SGL(@"settings.stats.period.month", @"Past month"), SGL(@"settings.stats.period.year", @"Past year"), SGL(@"settings.stats.period.all_time", @"All time")], *days = @[@7, @30, @365, @0];
    // Preserve the existing rolling 7/30/365-day periods used by the top lists.
    for (NSUInteger i = 0; i < names.count; i++) {
        NSString *name = names[i];
        int64_t back = [days[i] longLongValue] * 86400;
        SGModRow *row = SGPageRow(name, ^UIViewController *{ return periodPage(name, back ? (int64_t)time(NULL) - back : 0); });
        row.value = ^NSString *{ return values[name] ?: SGL(@"settings.stats.status.loading", @"Loading…"); };
        [periods addObject:row];
    }
    SGModRow *import = SGWithSymbol(SGStatActionRow(SGL(@"settings.stats.action.import", @"Import history"), SGL(@"settings.stats.action.import.subtitle", @"Vitrine JSON or Spotify JSON/ZIP"),
        ^NSString *{ return sg_importing ? SGL(@"settings.stats.status.importing", @"Importing…") : nil; }, nil), @"square.and.arrow.down");
    SGModRow *folder = SGActionRow(SGL(@"settings.stats.action.import_folder", @"Import a folder"), SGL(@"settings.stats.action.import_folder.subtitle", @"JSON files in the selected folder and its subfolders"), nil);
    SGModRow *export = SGWithSymbol(SGStatActionRow(SGL(@"settings.stats.action.export", @"Export history"), SGL(@"settings.stats.action.export.subtitle", @"Vitrine JSON, ready to import again"),
        ^NSString *{ return sg_exporting ? SGL(@"settings.stats.status.exporting", @"Exporting…") : nil; }, nil), @"square.and.arrow.up");
    SGModRow *erase = SGWithSymbol(SGActionRow(SGL(@"settings.stats.action.erase", @"Erase listening history"), nil, nil), @"trash");
    erase.color = SGRed();
    SGListeningPage *page = [[SGListeningPage alloc] initWithTitle:SGL(@"settings.stats.page.title", @"Listening stats") intro:nil sections:@[
        SGNotedSection(nil, @[SGSwitchRow(SGL(@"settings.stats.record.title", @"Record plays"), nil, SGKeyListeningStats)],
            SGL(@"settings.stats.record.footer", @"A play counts once it has run 30 seconds, or half of a shorter track. History stays on this phone unless you export it.")),
        SGSection(nil, periods),
        SGNotedSection(nil, @[
            SGStatRow(SGL(@"settings.stats.row.plays", @"Plays"), ^NSString *{ return values[@"plays"] ?: SGL(@"settings.stats.status.loading", @"Loading…"); }),
            SGStatRow(SGL(@"settings.stats.row.current_streak", @"Current streak"), ^NSString *{ return values[@"current"] ?: SGL(@"settings.stats.status.loading", @"Loading…"); }),
            SGStatRow(SGL(@"settings.stats.row.best_streak", @"Best streak"), ^NSString *{ return values[@"best"] ?: SGL(@"settings.stats.status.loading", @"Loading…"); }),
            SGStatRow(SGL(@"settings.stats.row.history", @"History"), ^NSString *{ return values[@"status"] ?: SGL(@"settings.stats.status.loading", @"Loading…"); }),
        ], SGL(@"settings.stats.section.history.footer", @"Streaks use local calendar days when plays ended. A current streak can end yesterday until you listen today. Import Spotify's account or extended streaming history, or Vitrine's own versioned history export. Duplicate plays are skipped. Large selections may need to be imported in smaller batches.")),
        SGSection(nil, @[import, folder, export]),
        SGSection(nil, @[erase]),
    ] footer:nil];
    page.loading = YES;
    __weak SGListeningPage *weakPage = page;
    page.refreshHistory = ^{
        SGListeningPage *page = weakPage;
        if (!page) return;
        NSUInteger generation = ++page.generation;
        page.loading = YES;
        values[@"status"] = SGL(@"settings.stats.status.loading", @"Loading…");
        [SGListeningLog() loadWithCompletion:^{
            if (SGListeningLog().loadError) {
                if (weakPage.generation != generation) return;
                [values removeAllObjects];
                for (NSString *key in [names arrayByAddingObjectsFromArray:@[@"plays", @"current", @"best"]]) values[key] = SGL(@"settings.stats.status.unavailable", @"Unavailable");
                values[@"status"] = SGL(@"settings.stats.status.error_retry", @"Could not load history. Reopen to retry.");
                weakPage.loading = NO;
                [weakPage.tableView reloadData];
                UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, values[@"status"]);
                return;
            }
            NSArray *snapshot = [SGListeningLog().plays copy];
            NSDate *now = NSDate.date;
            NSCalendar *calendar = [NSCalendar.currentCalendar copy];
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                SGListeningStreaks *streaks = SGStreaks(snapshot, now, calendar);
                NSMutableDictionary *summary = [NSMutableDictionary dictionary];
                for (NSUInteger i = 0; i < names.count; i++) {
                    int64_t back = [days[i] longLongValue] * 86400, since = back ? (int64_t)now.timeIntervalSince1970 - back : 0;
                    int64_t ms = 0;
                    for (SGPlay *play in snapshot) if (play.end >= since) ms += play.ms;
                    summary[names[i]] = duration(ms);
                }
                summary[@"plays"] = [NSString stringWithFormat:@"%lu", (unsigned long)snapshot.count];
                summary[@"current"] = daysText(streaks.current); summary[@"best"] = daysText(streaks.best);
                summary[@"status"] = snapshot.count ? SGL(@"settings.stats.status.on_phone", @"On this phone") : SGL(@"settings.stats.status.no_plays", @"No plays yet");
                dispatch_async(dispatch_get_main_queue(), ^{
                    SGListeningPage *page = weakPage;
                    if (!page || page.generation != generation) return;
                    [values addEntriesFromDictionary:summary];
                    page.loading = NO;
                    [page.tableView reloadData];
                });
            });
        }];
    };
    import.action = ^{ pickExport(weakPage, NO); };
    folder.action = ^{ pickExport(weakPage, YES); };
    export.action = ^{ exportHistory(weakPage); };
    erase.action = ^{ confirmErase(weakPage); };
    return page;
}
