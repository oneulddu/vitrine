# Listening stats harness

`SGPlayLog.m` run on the Mac against synthetic files in both shapes of Spotify's data export
(`StreamingHistory_music_*.json` and the extended `Streaming_History_Audio_*.json`), loose and inside zips
made by `/usr/bin/zip` both stored and deflated. Checks podcasts, nulls and plays under 30 s are left out,
that a play already recorded, the same play in both shapes and a second import of the same files add
nothing, that the log reads back what it wrote, and that the week, month, year and all-time tops add up.
It also times parsing, merging, loading and adding up 100k extended rows.

    ./build.sh && build/listening-stats

## Local history parity (0.51.0)

The production model now also provides pure `SGStreaks` and `SGHourlyStats` functions. Each already-counted
play belongs to its ending day/hour in the supplied calendar and timezone, including recorded short tracks.
Current streak includes today, or ends yesterday if today is empty. Best streak ignores future days.
There are always 24 hourly buckets; a repeated DST hour combines both occurrences. The existing rolling
7/30/365-day period cutoffs and top-list ordering are unchanged. The page formats hours using the user's
12/24-hour preference and exposes both plays and duration as ordinary accessible Settings rows.

Vitrine's own export is a JSON object, distinct from Spotify's array exports:

```json
{"format":"vitrine.listening-history","version":1,"plays":[{"end":1700000001,"ms":12500,"uri":"spotify:local:short","title":"Short track","artist":"Artist","album":""}]}
```

All six `SGPlay` fields are included, with Unix seconds and integer milliseconds. It contains no account,
credentials or settings. Unknown versions, malformed rows, invalid types and unsupported timestamps
(outside years 1–9999) reject the local file as a whole. Spotify's original filtering remains unchanged.
Spotify formats use the existing title/artist + 90-second deduplication for their minute precision and clock
drift. Vitrine backups compare all six persisted fields exactly, so legitimate nearby repeats survive while
selecting the same backup twice still adds nothing. Import never rewrites old TSV bytes.
The TSV's existing tab/newline-to-space normalization on disk is unchanged.

Import accepts selected JSON/ZIP files or a selected folder of JSON files. Security-scoped access and
coordinated file reads are balanced on a worker queue; traversal rejects symlinks, stays below selected
roots and ignores hidden/irrelevant files, packages and `__MACOSX`. Limits are eight entry levels, 10,000
visited entries, 1,000 files, 64 MiB per JSON, 256 MiB total input/expanded JSON and one million parsed plays.
ZIP decoding uses a fixed output buffer and charges failed decompression attempts to the same aggregate budget. Oversized or
unsupported items are skipped and reported. ZIP64 remains unsupported. Export refuses an over-limit
JSON rather than creating a backup the importer cannot read; the source history stays untouched.

Initial TSV loading, JSON parsing, folder walking, aggregation and export serialization run off main.
`SGPlayLog` remains main-owned, including merge and append. Async initial loading snapshots a file boundary
and retains records that arrive during loading; an intervening erase or synchronous load wins. Load errors
are explicit and retry on reopening the page. Export uses the system document exporter; its temporary file
is removed after completion or cancellation. No SQLite migration or Account/Plus dependency was added.

Additional harness cases cover spring/fall DST, a timezone that skips midnight, leap day, year boundaries,
non-Gregorian calendars, fractional timezones, yesterday/gap/empty/future streaks, hourly cutoffs, all-field
JSON round-trip, Unicode/escaped strings, short tracks, malformed/unknown JSON, duplicate import, append-only
byte preservation, selected-folder containment/depth/size limits, corrupt ZIP size declarations and async
load versus record/erase. The 100k benchmark also checks and times the new calendar aggregations.

2026-10-15 local verification: `./build.sh && build/listening-stats` passed all 71 checks.
For 100k rows (34.2 MB Spotify JSON): parse 426 ms, merge 289 ms, duplicate merge 133 ms,
TSV load 146 ms, top lists 153 ms, streaks plus hourly buckets 183 ms. These are Mac harness
measurements, not iPhone timings. `THEOS=$HOME/theos ./build-sim.sh` built successfully with
`-Wall -Werror`; the repository layer check and scoped `git diff --check` also passed.

## The page and the recorder in the simulator (`sim/`)

`ListeningStatsPage.m` on the real Settings/ framework, `ListeningStats.x` through Logos with `sim/stubs.m` standing in
for PlayerState.x and Spotify's player classes, and the page's picker kept rather than presented (the simulator's
picker is a remote service), so `pick` hands its delegate a JSON file and a zip as the system would.

    THEOS=$HOME/theos ./build-sim.sh
    xcrun simctl install <udid> build/sim/ListeningStatsHarness.app
    xcrun simctl launch <udid> com.vitrine.listeningstatsharness erase seed select=1.0 dump
    xcrun simctl spawn <udid> log show --last 2m --predicate 'eventMessage CONTAINS "[harness]"' --style compact

2026-10-05, iPhone 17 Pro on iOS 27.0: the page with seeded plays (week 1 h 36 min, month 2 h 12 min, as the seed
adds up), the Past week and All time pages (a long title wraps), an import of an extended file and a zip holding
`Spotify Account Data/StreamingHistory_music_0.json` (2 added, 1 skipped; the same again adds 0; the import row reads
Importing… until the merge, a second tap on it ignored meanwhile), and `record`: a
31 s play and one of 35 s around a 10 s pause written down (32.5 s and 36.8 s, `dispatch_after` running late), a
5 s skip left out.

The local parity batch also builds this simulator app with the real page and dark document presentation
helper. The original import row remains section 2, row 1; folder import is row 2, export row 3, current/best
streak rows 4/5. Each period's hourly page is section 0, row 2.

What it does not cover: Spotify's real player reporting, a real export from Spotify, cloud document-provider
access, or interactive system export completion/cancellation. The dated simulator observations above are
prior evidence, not a claim that the new picker paths were exercised on a device.
