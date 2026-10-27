#!/bin/bash
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d /tmp/vitrine-artist-artwork.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
FLAGS=(-target arm64-apple-ios17.0-macabi -isysroot "$SDK"
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks"
    -fobjc-arc -I ../../tweak/Sources
    -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics -framework AVFoundation -framework CoreMedia -framework CoreVideo)
xcrun -sdk macosx clang "${FLAGS[@]}" -DSG_MOTION_TEST_STORE main.m ../album-notes/catalog-boundary.m \
    ../../tweak/Sources/Core/SGLog.m \
    ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionCatalog.m \
    ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionClip.m ../../tweak/Sources/Shared/AdBlock/Protobuf.m \
    -o "$OUT/vitrine-artist-artwork-check"
VITRINE_TEST_ROOT="$OUT/catalog" "$OUT/vitrine-artist-artwork-check" fixtures/catalog.json
xcrun -sdk macosx clang "${FLAGS[@]}" late-check.m ../../tweak/Sources/Redesigned/Artist/ArtistArtwork.m \
    ../../tweak/Sources/Core/SGLog.m \
    ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionClip.m ../../tweak/Sources/Shared/AdBlock/Protobuf.m \
    -o "$OUT/vitrine-artist-late-check"
"$OUT/vitrine-artist-late-check"
xcrun -sdk macosx clang "${FLAGS[@]}" header-check.m ../../tweak/Sources/Redesigned/Artist/ArtistArtwork.m \
    ../../tweak/Sources/Core/SGLog.m \
    ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionClip.m ../../tweak/Sources/Shared/AdBlock/Protobuf.m \
    -o "$OUT/vitrine-artist-header-check"
"$OUT/vitrine-artist-header-check"
xcrun -sdk macosx clang "${FLAGS[@]}" download-check.m ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionStore.m \
    -o "$OUT/vitrine-artist-download-check"
VITRINE_TEST_ROOT="$OUT/downloads" "$OUT/vitrine-artist-download-check"
