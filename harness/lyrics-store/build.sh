#!/bin/sh
# Foundation-only production store and lyric models, without a Spotify app or home-folder data.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
mkdir -p "$HERE/build"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun -sdk macosx clang -isysroot "$SDK" -fobjc-arc -g -Wall -I"$SRC" \
    "$HERE/main.m" "$SRC/Shared/Lyrics/LyricsStore.m" "$SRC/Core/SGFileHash.m" \
    "$SRC/Shared/Lyrics/KaraokeTiming.m" "$SRC/Shared/AdBlock/Protobuf.m" \
    -framework Foundation -o "$HERE/build/lyrics-store"
