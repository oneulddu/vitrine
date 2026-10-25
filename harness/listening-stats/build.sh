#!/bin/sh
# Builds the listening stats harness for the Mac: SGPlayLog.m as the tweak compiles it, and main.m.
set -e
cd "$(dirname "$0")"
OUT=${BUILD_DIR:-build}
mkdir -p "$OUT"
xcrun clang -fobjc-arc -O2 -Wall -Werror -I ../../tweak/Sources -framework Foundation \
    main.m ../../tweak/Sources/Shared/ListeningStats/SGPlayLog.m ../../tweak/Sources/Core/SGLocalize.m -o "$OUT/listening-stats"
