#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT=$(mktemp -d /tmp/vitrine-song-audio.XXXXXX)
SUITE="dev.vitrine.song-audio.$(basename "$OUT")"
trap 'rm -rf "$OUT"; defaults delete "$SUITE"' EXIT
SRC="$HERE/../../tweak/Sources"
xcrun clang -fobjc-arc -I"$HERE/stub" -I"$SRC" -I"$SRC/Shared/Player" -framework Foundation -framework AudioToolbox \
    "$HERE/main.m" "${SONG_AUDIO_SOURCE:-$SRC/Shared/Player/SpeedPitchSongs.m}" \
    -o "$OUT/vitrine-song-audio-retention"
"$OUT/vitrine-song-audio-retention" "$SUITE" write
"$OUT/vitrine-song-audio-retention" "$SUITE" read
