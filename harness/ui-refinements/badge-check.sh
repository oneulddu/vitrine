#!/bin/bash
# Both production badge hooks, independently gated, with exact Spotify view identities.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT=$(mktemp -d /tmp/vitrine-explicit-badge.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
LOGOS=${THEOS:-$HOME/theos}/bin/logos.pl
"$LOGOS" -c generator=internal "${NATIVE_BADGE:-$SRC/Native/Appearance/ExplicitBadge.x}" > "$OUT/Native.m"
"$LOGOS" -c generator=internal "${REDESIGN_BADGE:-$SRC/Redesigned/Kit/SGRExplicitBadge.x}" > "$OUT/Redesign.m"
xcrun clang -target arm64-apple-ios17.0-macabi -fobjc-arc -O0 -g -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"$SRC" -I"$SRC/Native/Appearance" -I"$SRC/Redesigned/Kit" \
    "$HERE/badge-check.m" "$OUT/Native.m" "$OUT/Redesign.m" "$SRC/Core/SGPrefs.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation -o "$OUT/check"
"$OUT/check"
LOOK=redesign "$OUT/check"
