#!/bin/sh
# Recent accent colors (both looks) and the album play-count place, as plain code on the Mac (Mac Catalyst, for
# the UIKit the headers import). No simulator. Run from anywhere; OUT moves the build directory.
set -eu
cd "$(dirname "$0")"
SRC=../../tweak/Sources
OUT=${OUT:-build}
mkdir -p "$OUT"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target arm64-apple-ios17.0-macabi -isysroot "$SDK" -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-unused-parameter -I "$SRC" \
    rules-check.m "$SRC/Core/SGPrefs.m" "$SRC/Native/Appearance/AccentHistory.m" "$SRC/Redesigned/Kit/SGRAccentHistory.m" \
    "$SRC/Redesigned/Album/AlbumPlaysPlace.m" -framework Foundation -o "$OUT/ui-refinements-rules-check"
"$OUT/ui-refinements-rules-check"
