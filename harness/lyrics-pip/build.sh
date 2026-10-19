#!/bin/sh
# Builds the lyrics PiP text harness for the Mac: LyricsPiPText.m as the tweak compiles it, with
# KaraokeTiming.m and Protobuf.m to link. Lyrics.h imports UIKit, so build for Mac Catalyst.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
mkdir -p "$HERE/build"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun -sdk macosx clang -target arm64-apple-ios17.0-macabi -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -fobjc-arc -g -Wall \
    -I"$SRC" \
    "$HERE/main.m" "$SRC/Shared/LyricsPiP/LyricsPiPText.m" "$SRC/Shared/LyricsPiP/LyricsPiPFrame.m" \
    "$SRC/Shared/Lyrics/KaraokeTiming.m" "$SRC/Shared/AdBlock/Protobuf.m" \
    -framework UIKit -framework Foundation -framework CoreText -framework ImageIO -framework CoreGraphics \
    -o "$HERE/build/lyrics-pip"
