#!/bin/sh
# Runs the production Native helper on Foundation with mock view trees; no simulator or app.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
OUT=$(mktemp -d "${TMPDIR:-/tmp}/vitrine-native-declutter.XXXXXX")
trap 'rm -rf "$OUT"' EXIT HUP INT TERM
xcrun clang -fobjc-arc -O0 -g -target arm64-apple-macos13.0 \
    -I "$HERE/shim" -I "$SRC" \
    "$HERE/check.m" "$SRC/Native/Declutter/Declutter.m" \
    -framework Foundation -framework CoreGraphics -o "$OUT/check"
"$OUT/check"
