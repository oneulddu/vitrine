# Offline lyrics store

Run from the Project root:

```sh
HARNESS_BUILD_DIR=$(mktemp -d /tmp/fix-offline-lyrics.XXXXXX) sh harness/lyrics-store/build.sh
python3 -B harness/lyrics-store/mutation-check.py
```

The Mac Catalyst command-line harness runs without a simulator or network. It links
the actual store and lyric models and extracts the production credit registry
from `LyricsSources.m`, leaving the unrelated provider walk and UI unlinked.
Its unique build directory is removed on exit; lyric files use isolated temporary
directories, never the user's store.

Checks cover provider translations (including backing lines), credit titles/URLs
and mandatory attribution, generated-content exclusion, literal old-format records,
malformed/oversized optional fields, byte accounting, single-record overflow,
oldest-first eviction, main-queue completion and binary plist storage.
Rejected asynchronous loads leave the live credit untouched, including when the
stored link field is malformed; accepted loads explicitly register returned metadata.
The mutation check compiles isolated store copies with translation or credit-link
persistence removed, or premature credit registration restored; each must fail at
its corresponding behavior assertion.
Spotify's actual offline presentation and link opening remain device checks.
