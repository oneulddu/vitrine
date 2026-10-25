#!/bin/sh
# Cached release selection only: no simulator, app UI or network request.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT=$(mktemp -d "${TMPDIR:-/tmp}/vitrine-update-check.XXXXXX")
trap 'rm -rf "$OUT"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target arm64-apple-ios17.0-macabi -fobjc-arc -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -I"$SRC" -DSG_VERSION='"1.0.0"' \
    "$SRC/App/About/Update.m" "$SRC/Core/SGPrefs.m" "$SRC/Core/SGLocalize.m" \
    "$HERE/offline-check.m" \
    -framework UIKit -framework Foundation -o "$OUT/check"
"$OUT/check"
