#!/bin/sh
# Left, Centered and Poster draw every case of fixtures.h pixel for pixel as SGLyricsClip.m drew them at BASE, the
# commit before Messages and Vinyl (frames.m says how). BASE=<commit> compares with another; SRC=<tree> checks another
# source tree (mutations.py). Builds in a temporary directory, removed after.
set -e
cd "$(dirname "$0")"
ROOT=$(git rev-parse --show-toplevel)
BASE=${BASE:-0e2659d03142a821b0af2c5a1022a3ec09b203e0}
SRC=${SRC:-$ROOT/tweak/Sources}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/lyrics-clip-unchanged.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/base/Shared/LockScreenLyrics" "$WORK/frames"
for f in SGLyricsClip.h SGLyricsClip.m; do
    git -C "$ROOT" show "$BASE:tweak/Sources/Shared/LockScreenLyrics/$f" > "$WORK/base/Shared/LockScreenLyrics/$f"
done
FRAMEWORKS="-framework Foundation -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework CoreImage
    -framework CoreText -framework CoreGraphics -framework Accelerate -framework AppKit"
# The base's header first, so frames.m and its SGLyricsClip.m take it; LyricsBackground from the tree checked.
xcrun clang -fobjc-arc -O2 -Wno-deprecated-declarations -DSG_BASELINE -I "$WORK/base" -I "$SRC" $FRAMEWORKS \
    frames.m "$WORK/base/Shared/LockScreenLyrics/SGLyricsClip.m" "$SRC/Shared/LyricsBackground/LyricsBackground.m" -o "$WORK/base-frames"
xcrun clang -fobjc-arc -O2 -Wno-deprecated-declarations -I "$SRC" $FRAMEWORKS \
    frames.m "$SRC/Shared/LockScreenLyrics/SGLyricsClip.m" "$SRC/Shared/LyricsBackground/LyricsBackground.m" -o "$WORK/frames-now"
"$WORK/base-frames" write "$WORK/frames"
"$WORK/frames-now" check "$WORK/frames"
