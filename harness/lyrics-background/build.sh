#!/bin/sh
set -e
cd "$(dirname "$0")"
OUT=${OUT:-build}
mkdir -p "$OUT"
xcrun clang -fobjc-arc -O2 -I ../../tweak/Sources \
    main.m ../../tweak/Sources/Shared/LyricsBackground/LyricsBackground.m \
    -framework Foundation -framework CoreGraphics -framework Accelerate -o "$OUT/lyrics-background"
"$OUT/lyrics-background"
