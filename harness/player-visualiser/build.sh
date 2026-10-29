#!/bin/sh
# Builds the Visualizer view (Redesigned/Player/PlayerVisualiser.m) for the Mac Catalyst under stubs for the
# player, lyrics store and tokens it reads, and runs the checks.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
OUT=${OUT:-$HERE/build}
mkdir -p "$OUT"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun -sdk macosx clang -target arm64-apple-ios17.0-macabi -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -fobjc-arc -g -Wall -Wextra \
    -Wno-unused-parameter -I"$SRC" -I"$SRC/Redesigned/Player" -I"$HERE/.." \
    "$HERE/main.m" "$SRC/Redesigned/Player/PlayerVisualiser.m" "$SRC/Redesigned/Player/SGRSpectrum.m" \
    "$SRC/Shared/Lyrics/KaraokeTiming.m" "$SRC/Shared/AdBlock/Protobuf.m" \
    -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics -framework Accelerate \
    -o "$OUT/player-visualiser"
"$OUT/player-visualiser"
