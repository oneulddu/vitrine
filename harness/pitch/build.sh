#!/bin/sh
# Builds the pitch harness for the Mac: SGTimePitch.m as the tweak compiles it, and main.m.
set -e
cd "$(dirname "$0")"
MAIN=main.m
if [ "$1" = lifetime ]; then MAIN=lifetime.m; fi
OUT=${OUT:-build/pitch}
mkdir -p "$(dirname "$OUT")"
xcrun clang -fobjc-arc -O2 -I ../../tweak/Sources -framework Foundation -framework AudioToolbox \
    "$MAIN" ../../tweak/Sources/Shared/Player/SGTimePitch.m -o "$OUT"
