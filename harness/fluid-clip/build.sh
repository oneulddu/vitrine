#!/bin/sh
# Builds the Fluid clip harness for the Mac: SGFluidClip.m as the tweak compiles it, and main.m.
set -e
cd "$(dirname "$0")"
OUT=${OUT:-build}
mkdir -p "$OUT"
xcrun clang -fobjc-arc -O2 -Wno-deprecated-declarations -I ../../tweak/Sources \
    -framework Foundation -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework CoreImage \
    -framework CoreText -framework CoreGraphics -framework ImageIO -framework UniformTypeIdentifiers -framework Accelerate \
    main.m ../../tweak/Sources/Shared/AnimatedArtwork/SGFluidClip.m ../../tweak/Sources/Shared/LockScreenLyrics/SGLyricsClip.m \
    ../../tweak/Sources/Shared/LyricsBackground/LyricsBackground.m \
    -o "$OUT/fluid-clip"
