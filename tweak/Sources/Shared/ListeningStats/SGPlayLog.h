// The plays Listening stats counts, kept on the phone: recorded as they happen, merged in from Spotify's own
// data export, and added up into tops, chart bars and streaks for a calendar period. Foundation only, so the Mac harness
// (harness/listening-stats) builds it as the tweak does.
//
// The log is a text file of one play per line, appended to as plays end, so recording costs one write:
//     end <tab> ms <tab> uri <tab> title <tab> artist <tab> album
// `end` is when the play stopped, in Unix seconds, which is what both of Spotify's export shapes record.
//
// Threading: an SGPlayLog is used from one thread (the main one in the tweak). The parsers are pure and
// run on any.
#import <Foundation/Foundation.h>

@interface SGPlay : NSObject
@property (nonatomic) int64_t end;   // Unix seconds, when the play stopped
@property (nonatomic) int64_t ms;    // how long it was listened to
@property (nonatomic, copy) NSString *uri, *title, *artist, *album;   // uri and album may be empty, never nil
// Parser-only provenance. Vitrine backups retain distinct nearby plays and deduplicate exact rows;
// Spotify exports use the tolerant title/artist/time match described on -merge:.
@property (nonatomic) BOOL exactImport;
@end

FOUNDATION_EXPORT NSNotificationName const SGPlayLogDidChangeNotification;

// A play counts once it has run 30 s, or half of a track shorter than a minute.
enum { SGPlayMinimumMs = 30000 };
BOOL SGPlayCounts(double listenedSeconds, double durationSeconds);

// Vitrine's versioned history object, or either Spotify shape: StreamingHistory_music_*.json (endTime,
// artistName, trackName, msPlayed) or the extended Streaming_History_Audio_*.json (ts, ms_played,
// master_metadata_*, spotify_track_uri). For Spotify only, podcasts and plays under SGPlayMinimumMs
// are left out. Nil when unsupported, malformed or over the file/row limits below.
NSArray<SGPlay *> *SGPlaysFromExport(NSData *json);
// Vitrine's version 1 history envelope (not a Spotify export). All six SGPlay fields are retained,
// including counted short tracks. Unknown versions or malformed local rows reject the whole file.
NSData *SGHistoryJSON(NSArray<SGPlay *> *plays, NSError **error);
// The .json files inside a zip, such as the export as Spotify mails it. Empty when it is not a zip.
NSArray<NSData *> *SGJSONFilesInZip(NSData *zip);

@interface SGHistoryImport : NSObject
@property (nonatomic, copy) NSArray<SGPlay *> *plays;
@property (nonatomic) NSUInteger files, skipped;
@end
// File IO/parsing: call off main. Selected files or folders only; no symlinks, hidden files or packages.
// Security-scoped access and coordinated reads are balanced here. Limits: 8 levels, 10k visited
// entries, 1000 files, 64 MiB per JSON, 256 MiB total input/expanded data and one million plays.
SGHistoryImport *SGReadHistoryURLs(NSArray<NSURL *> *urls);

@interface SGPlayLog : NSObject
- (instancetype)initWithPath:(NSString *)path;
// Every play, read from the file the first time it is asked for.
@property (nonatomic, readonly) NSArray<SGPlay *> *plays;
@property (nonatomic, readonly) NSError *loadError;
// Main-thread entry/completion; initial TSV parsing happens off main. Records arriving meanwhile
// remain in the append-only log and in the completed snapshot. A page should wait before reading plays.
- (void)loadWithCompletion:(void (^)(void))completion;
- (void)record:(SGPlay *)play;
// Adds the plays the log does not have yet, and answers how many that was. Spotify rows match the same
// track and artist within 90 s, covering basic-export minute precision and clock drift. Vitrine rows
// match all six persisted fields exactly, so a backup restores legitimate nearby repeats losslessly.
- (NSUInteger)merge:(NSArray<SGPlay *> *)plays;
- (void)erase;
@end

// One line of a top list: a track (detail is its artist), an artist (no detail) or an album (its artist).
@interface SGStatEntry : NSObject
@property (nonatomic, copy) NSString *name, *detail;
@property (nonatomic) NSUInteger plays;
@property (nonatomic) int64_t ms;
@end

@interface SGStats : NSObject
@property (nonatomic) NSUInteger plays;
@property (nonatomic) int64_t ms;
// Most played first, then most listened to; at most `top` of each.
@property (nonatomic, copy) NSArray<SGStatEntry *> *tracks, *artists, *albums;
@end

// The plays that ended at or after `since` (Unix seconds; 0 for all of them), added up.
SGStats *SGStatsSince(NSArray<SGPlay *> *plays, int64_t since, NSUInteger top);
// The plays that ended in [start, end) (Unix seconds; INT64_MAX for no end), added up the same way.
SGStats *SGStatsBetween(NSArray<SGPlay *> *plays, int64_t start, int64_t end, NSUInteger top);

@interface SGListeningStreaks : NSObject
@property (nonatomic) NSUInteger current, best;
// The first and last local day (each its start) of the current streak and of the best one, the latest
// best on a tie; nil while the streak is 0.
@property (nonatomic, strong) NSDate *currentStart, *currentEnd, *bestStart, *bestEnd;
@end
// Inputs are already-counted log records (do not apply the Spotify import threshold again).
// Each play belongs to its ending local day/hour. Streaks ignore future days; current may end yesterday.
SGListeningStreaks *SGStreaks(NSArray<SGPlay *> *plays, NSDate *now, NSCalendar *calendar);
// Always 24 entries indexed 0…23, including empty hours; repeated DST hours share a bucket.
NSArray<SGStatEntry *> *SGHourlyStats(NSArray<SGPlay *> *plays, int64_t since, NSCalendar *calendar);
// The same for the plays that ended in [start, end) (INT64_MAX for no end).
NSArray<SGStatEntry *> *SGHourlyStatsBetween(NSArray<SGPlay *> *plays, int64_t start, int64_t end, NSCalendar *calendar);

// The calendar periods the page steps through, in the supplied calendar and its time zone. A week starts on
// the calendar's firstWeekday; every period starts at the start of its first day, which is 01:00 on a day a
// time zone skips midnight, so DST weeks and days are an hour short or long.
typedef NS_ENUM(NSInteger, SGStatsPeriod) { SGStatsPeriodWeek, SGStatsPeriodMonth, SGStatsPeriodYear };
// The period holding `date`, as [its start, the next one's start). Nil outside what NSCalendar can represent.
NSDateInterval *SGPeriodInterval(SGStatsPeriod period, NSDate *date, NSCalendar *calendar);
// The period `steps` whole periods after (negative: before) the one holding `date`.
NSDateInterval *SGPeriodStep(SGStatsPeriod period, NSDate *date, NSInteger steps, NSCalendar *calendar);

// One bar of a period's chart: a local day of a week or month, or a month of a year.
@interface SGStatBucket : NSObject
@property (nonatomic) int64_t start, end;   // Unix seconds, [start, end)
@property (nonatomic) NSUInteger plays;
@property (nonatomic) int64_t ms;
@end
// The days (week, month) or months (year) of the period holding `date`, in order and empty ones included,
// each with the plays that ended in it. Empty when the period cannot be represented.
NSArray<SGStatBucket *> *SGPeriodBuckets(NSArray<SGPlay *> *plays, SGStatsPeriod period, NSDate *date, NSCalendar *calendar);
