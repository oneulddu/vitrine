#!/bin/sh
set -eu
cd "$(dirname "$0")"
OUT=${OUT:-build}
mkdir -p "$OUT"
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-unused-parameter -I ../../tweak/Sources -I ../../tweak/Sources/Core \
    -framework Foundation check.m ../../tweak/Sources/Core/SGPrefs.m -o "$OUT/check"
"$OUT/check"
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations -I ../../tweak/Sources \
    -framework Foundation counters.m ../../tweak/Sources/Core/SGCounterStore.m ../../tweak/Sources/Core/SGFileHash.m -o "$OUT/counters"
"$OUT/counters"
