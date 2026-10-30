#!/bin/sh
# The artist page's picture-aware photo (Redesigned/Kit/SGRCoverRead.h's SGRPhotoRead, Redesigned/Artist/ArtistHeader.x)
# as Mac Catalyst programs; no simulator. photo-read-check reads the photos of photo-fixtures.h; photo-hero-check shows
# them in the artist's hero on a page with its field, with the setting on and off, a photo swapped mid read and Apple
# Music's photo replaced by Spotify's mid read; the hero above its dissolve has to be the same bytes on and off, only
# the page's colour may differ. Then mutated copies of the sources have to fail: the face left in the foot, and the
# hero taking a stale read.
# With SHOTS set to a folder, each of the four photos is drawn on the page with the setting off and on into it.
# With BASELINE set to a Git revision, the off page of that revision's sources is drawn too and must be the same bytes.
# Needs Theos ($THEOS, else ~/theos). Builds into a temporary folder (or OUT, kept).
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
LOGOS=${THEOS:-$HOME/theos}/bin/logos.pl
if [ -n "${OUT:-}" ]; then mkdir -p "$OUT"; else OUT=$(mktemp -d /tmp/vitrine-photo-check.XXXXXX); trap 'rm -rf "$OUT"' EXIT; fi
SDK=$(xcrun --sdk macosx --show-sdk-path)
CC="xcrun clang -target arm64-apple-ios17.0-macabi -fobjc-arc -g -O0 -isysroot $SDK -iframework $SDK/System/iOSSupport/System/Library/Frameworks -Wno-deprecated-declarations -Wno-objc-property-implementation -Wno-incomplete-implementation -Wno-protocol"
FRAMEWORKS="-framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreImage -framework Foundation -framework Vision"
PHOTOS="faceAtBottom largeFace noFace dark"

# read_check <SGRCoverRead.m> <out dir>: photo-read-check built with that copy of the read.
read_check() {
    mkdir -p "$2"
    $CC -DSGR_COVER_READ_TEST -I"$SRC" -I"$SRC/Redesigned/Kit" "$HERE/photo-read-check.m" "$1" "$SRC/Redesigned/Kit/SGRTokens.m" \
        "$SRC/Core/SGLog.m" "$SRC/Core/SGPrefs.m" $FRAMEWORKS -o "$2/photo-read-check"
}

# hero <sources> <out dir> [hero mutant]: the hero and the field generated from <sources> with photo-hero-check.m for main.
hero() {
    src=$1 dir=$2
    mkdir -p "$dir/gen"
    for f in Redesigned/Artist/ArtistHeader.x Redesigned/Artist/ArtistField.x; do
        "$LOGOS" -c generator=internal "$src/$f" > "$dir/gen/$(basename "$f" .x).m"
    done
    if [ -n "${3:-}" ]; then python3 "$HERE/photo-mutation.py" "$3" "$dir/gen/ArtistHeader.m"; fi
    # An earlier revision may have no picture read.
    cover=""
    if [ -f "$src/Redesigned/Kit/SGRCoverRead.m" ]; then cover="$src/Redesigned/Kit/SGRCoverRead.m"; fi
    $CC -DSGR_COVER_READ_TEST -I"$src" -I"$src/Redesigned/Artist" "$HERE/photo-hero-check.m" "$HERE/photo-stubs.m" "$dir"/gen/*.m $cover \
        "$src"/Redesigned/Artist/ArtistArtwork.m "$src"/Core/SGLog.m "$src"/Core/SGPrefs.m \
        "$src"/Redesigned/Kit/SGRTokens.m "$src"/Redesigned/Kit/SGRPalette.m "$src"/Redesigned/Kit/SGRField.m "$src"/Redesigned/Kit/SGRFlow.m \
        "$src"/Redesigned/Kit/SGRFluid.m "$src"/Redesigned/Kit/SGRFluidGPU.m "$src"/Redesigned/Kit/SGRHeroVeil.m \
        "$src"/Shared/AnimatedArtwork/SGMotionClip.m "$src"/Shared/AdBlock/Protobuf.m \
        $FRAMEWORKS -framework Metal -framework AVFoundation -framework CoreMedia -framework CoreVideo -o "$dir/photo-hero-check"
}

ON="-spotifyglass.redesign.artist.adaptivePhoto YES"

read_check "$SRC/Redesigned/Kit/SGRCoverRead.m" "$OUT/read"
"$OUT/read/photo-read-check"

hero "$SRC" "$OUT/hero"
mkdir -p "$OUT/shots"
for photo in $PHOTOS; do
    "$OUT/hero/photo-hero-check" on "$photo" "$OUT/shots" $ON
    "$OUT/hero/photo-hero-check" off "$photo" "$OUT/shots"
    if ! cmp -s "$OUT/shots/$photo-on-photo.png" "$OUT/shots/$photo-off-photo.png"; then
        echo "[harness] FAIL $photo: the hero above its dissolve is drawn differently with the setting on"
        exit 1
    fi
    echo "[harness] PASS $photo: the hero above its dissolve is the same bytes on and off"
    if [ -n "${SHOTS:-}" ]; then cp "$OUT/shots/$photo-on.png" "$OUT/shots/$photo-off.png" "$SHOTS/"; fi
done
"$OUT/hero/photo-hero-check" swap $ON
"$OUT/hero/photo-hero-check" source $ON -spotifyglass.redesign.artist.applePhoto YES

# expect_fail <name> <log> <message> <program and arguments...>: the program has to fail, at the assertion named.
expect_fail() {
    name=$1 log=$2 message=$3
    shift 3
    if "$@" > "$log" 2>&1; then
        echo "[harness] FAIL mutation $name survived"
        exit 1
    fi
    if ! grep -q "FAIL.*$message" "$log"; then
        cat "$log"
        echo "[harness] FAIL mutation $name did not fail at \"$message\""
        exit 1
    fi
    echo "[harness] PASS mutation $name: rejected at \"$message\""
}

mkdir -p "$OUT/exclusion"
cp "$SRC/Redesigned/Kit/SGRCoverRead.m" "$OUT/exclusion/SGRCoverRead.m"
python3 "$HERE/photo-mutation.py" exclusion "$OUT/exclusion/SGRCoverRead.m"
read_check "$OUT/exclusion/SGRCoverRead.m" "$OUT/exclusion"
expect_fail exclusion "$OUT/exclusion.log" "face exclusion" "$OUT/exclusion/photo-read-check"
hero "$SRC" "$OUT/stale" stale
expect_fail stale "$OUT/stale.log" "stale completion" "$OUT/stale/photo-hero-check" swap $ON

if [ -n "${BASELINE:-}" ]; then
    git -C "$HERE/../.." archive --prefix=baseline/ "$BASELINE" tweak/Sources | tar -x -C "$OUT"
    hero "$OUT/baseline/tweak/Sources" "$OUT/baseline/hero"
    mkdir -p "$OUT/baseline/shots"
    "$OUT/baseline/hero/photo-hero-check" off noFace "$OUT/baseline/shots"
    if ! cmp -s "$OUT/shots/noFace-off.png" "$OUT/baseline/shots/noFace-off.png"; then
        echo "[harness] FAIL the artist page with the setting off is not drawn as at $BASELINE"
        exit 1
    fi
    echo "[harness] PASS setting off: the artist page is drawn byte for byte as at $BASELINE"
fi
