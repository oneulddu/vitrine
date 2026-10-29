# Local files check

`./build.sh` checks `Shared/LocalFiles/LocalFiles.m` as the tweak compiles it: a `spotify:local:` URI
read back into its names (form decoded, a `%3A` in a title too), an edit laid over them, and the lyrics
key each edit gives. A rename gets a new key (`<uri>#<number>`), the same names saved again or a new
cover with them keep it, a cover alone on an unedited file leaves the bare URI, and names back to the
file's own go back to it. It also checks a stored cover's `spotify:localfileimage:` address and its way
back, that no other path comes back through it, and that a dropped or replaced legacy cover is removed.

It runs on the Mac as a Mac Catalyst binary with `CFFIXED_USER_HOME` set to `build/home`, so its
defaults and its covers never reach the Mac's own.

It then builds `lrc.m` against `LocalLyrics.m`, the engine's line timing and `SGTTML.m`: the validator
(empty, 1 MB + 1, binary garbage, blank text, UTF-16 with a BOM, 8 GiB sparse input refused without
loading it), the three readings by content (a TTML sample, an LRC sample, a plain text sample with CRLF
and blank lines, and the plain-text fallback of a TTML or LRC document that holds no line, an LRC whose
timestamps are all malformed included: its stamps and tags go and its words stay), an import kept under
what it holds (a taken name numbered), a file linked to a local file through a rename's key and gone with a
delete, a paste held to the same rules and kept under what it holds too, and the match by title and artist,
folded, with an "Artist - Title" name's sides worked out from the track.

Replacing a linked file writes and links the new one and puts the old file's name on a retired list of its
own, deleting nothing at that step. Every change to the store — a name's allocation and its file, the links,
the retired list, a delete and the launch's retire step — runs on one serial queue, so the step always runs
first and never beside an import that reuses a name it is about to remove; every store notification is
posted on the main queue. The check walks each case over separate launches of the same binary (a by-name
import and a hand-copied file surviving three, the retired file removed once its link has moved on, a link
update lost to a crash keeping the old file while its link still names it, and a retired directory or
symlink never deleted), plus the reuse race and the notification's thread. A link whose file is missing
gives no lines rather than another song's. With the write injected to fail, the old file, its link and its
lines stand as they were.

It does not cover Spotify's image-loader hook or metadata consumers, the lyrics engine asking for the new key
(`Shared/Lyrics/KaraokeSource.x`) or the Imported lyrics files page.

Cover Save writes a fresh UUID JPEG synchronously on main, publishes its reference, then removes the
previous file in the same turn. Picker work already limits the image to 1200 pixels off main.
The check verifies bounded main-thread encoding, legacy UUID loading, reference-before-removal,
and a changed cover URL on every replacement. There is no sweep or deterministic naming.
Unavailable/invalid/protected initial cache reads still recover later.
Cover loading remains asynchronous. `now-playing.m` runs the real Logos observer with a
fake player/extras sink: it blocks a worker read across a track change, rejects the stale result, then
verifies edited/original-title artwork and the synchronous memory-only system artwork callback.

Imports now read at most 1 MB + 1 on a worker queue and complete on main. The LRC check includes an
8 GiB sparse input rejected without loading it, and a blocked old read across delete/reimport to prove
that an invalidated cache cannot be repopulated with old lyrics. `BUILD_DIR` selects an isolated output/home
directory for a run without touching existing harness artifacts.

`cover.m` also exercises the real fallback-cover resolver against a stand-in for Spotify 9.1.90's
unchecked `spt_localFileImagePath`. Before the fix, a one-part metadata URL reproduces the recorded
`NSRangeException` (index 2 in an array of one). It checks malformed and unrelated URLs, valid absolute
paths/file URLs/escaped local-image URIs, the next metadata field, Now Playing fallback and an edited
cover taking precedence. The resolver must never call the unchecked parser. These are resolver tests,
not a full Spotify playback test on an iPhone.
Metadata file covers use the bounded ImageIO reader on a worker; layouts synchronously reuse its
current-track cache. The check rejects main-thread reads, retains cached images after file removal,
remembers failed reads past the old retry interval, and drops an in-flight result across A → B → A.
`watcher.m` runs the real native watcher (`Native/LocalFiles/LocalCover.x` through Logos) over the production
resolver, with Spotify's list, cell and cover-tilt classes as doubles under their runtime names. Two local tracks share a
title and artist; the second shows the first's artwork, the watcher's 0 and 1.5 s retries pass, and the second's own
artwork then reaches the now playing info with only the info-changed notification posted: the displayed cover must
become it with no layout and no playback change.
The native image-view publisher is exercised with the production resolver: provisional red system
artwork upgrades to a late blue metadata thumbnail, but an image installed by Spotify remains intact.
`bridge.m` compiles the real redesigned Logos artwork bridge, local resolver and `SGRArtworkField`.
With palette rendering doubled, it verifies that provisional red and exact blue have different
identities and the field accepts the upgrade, then rejects late provisional resolver/screen replies.

## Edit info in the simulator

`sim/build-sim.sh <udid>` builds `EditInfoMenu.x` and `LocalFiles.m` as the tweak compiles them into an
app with a mock of Spotify's context menu sheet over a player that plays a local file, runs it, and saves
a screenshot at each step into `build/sim/shots/`. The script taps Edit info, which closes the menu and
brings up the editor sheet. Then it types a name and picks a cover (neither is stored before Save),
saves, opens the editor again, restores the file's info and saves, and last tries to swipe away
unsaved changes, which must ask first. Each step logs `PASS` or `FAIL`. `large` runs it once at the
largest accessibility text size, where each label goes above its field, and sets the size back.

    THEOS=$HOME/theos sim/build-sim.sh <udid> [large]

It does not cover the pickers themselves, the keyboard over the sheet, or Spotify's own menu closing.

## The lyrics pages in the simulator

`lyrics/build.sh <udid>` builds the native look's lyrics page for a local file
(`Native/LocalFiles/LocalLyricsPage.m`) with `LocalLyrics.m` as the tweak compiles them, over a stand-in
player whose clock runs at four times the song's speed. It imports and links an `.lrc` file, opens the
page, checks that every line shows and that the line being sung is the one lit, then moves to a track with
no file and checks that the lines go. `settings` as the second argument shows the Imported LRC files page
instead. Screenshots go into `build/lyrics/shots/`.

    lyrics/build.sh <udid> [settings]

It does not cover the button on Spotify's footer, Files, or a swipe to delete.
