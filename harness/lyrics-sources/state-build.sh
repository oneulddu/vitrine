#!/bin/sh
# Run the keeper and walk on the Mac, omitting only the Logos hooks that need Spotify.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
mkdir -p "$HERE/build"
sed '/^%hook SPTEsperantoPlayer/,$d' "$SRC/Shared/Lyrics/KaraokeSource.x" > "$HERE/build/karaoke.inc"
sed '/^#pragma mark - hooks/,$d' "$SRC/Shared/LyricsSources/LyricsHook.x" > "$HERE/build/lyrics-hook.inc"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun -sdk macosx clang -target arm64-apple-ios17.0-macabi -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -fobjc-arc -g -Wall -Wno-unused-function -Wno-unused-variable \
    -I"$SRC" -I"$SRC/Shared/Lyrics" -I"$SRC/Shared/LyricsSources" -I"$HERE/build" -DSG_VERSION=\"0.0.0\" \
    "$HERE/state-check.m" "$SRC/Shared/LyricsSources/LrcLib.m" "$SRC/Shared/Lyrics/KaraokeTiming.m" \
    "$SRC/Shared/Lyrics/LyricsLanguage.m" "$SRC/Shared/Lyrics/Romanise.m" "$SRC/Shared/AdBlock/Protobuf.m" "$SRC/Core/SGPrefs.m" \
    -framework UIKit -framework Foundation -framework NaturalLanguage -framework AVFoundation -o "$HERE/build/state-check"
"$HERE/build/state-check"
