#!/bin/sh
# Mutation check for check.sh: each mutation of GestureHold.m, made in a temporary copy of the sources, must make
# the check fail. The tweak's own files are never touched.
set -eu
cd "$(dirname "$0")"
REAL=$(cd ../../tweak/Sources && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mutate() {   # name, text to find, text to put
    rm -rf "$WORK/Sources"
    mkdir -p "$WORK/Sources"
    cp -R "$REAL/Core" "$WORK/Sources/Core"
    mkdir -p "$WORK/Sources/Shared"
    cp -R "$REAL/Shared/Gestures" "$WORK/Sources/Shared/Gestures"
    python3 - "$WORK/Sources/Shared/Gestures/GestureHold.m" "$2" "$3" <<'PY'
import sys
path, old, new = sys.argv[1:]
text = open(path, encoding="utf-8").read()
assert text.count(old) == 1, old
open(path, "w", encoding="utf-8").write(text.replace(old, new))
PY
    if SRC="$WORK/Sources" OUT="$WORK/build" ./check.sh >/dev/null 2>&1; then
        echo "MUTATION SURVIVED: $1"
        exit 1
    fi
    echo "killed: $1"
}

SRC="$REAL" OUT="$WORK/build-real" ./check.sh
mutate "default choice is 3x" "kDefaultHoldSpeedChoice = 1;" "kDefaultHoldSpeedChoice = 2;"
mutate "no clamp at the top" "MIN((NSInteger)SGGestureHoldSpeedChoices().count - 1, choice)" "choice"
mutate "no clamp at the bottom" "MAX(0, MIN(" "MAX(-9, MIN("
mutate "hold off unless switched on" "SGEnabled(SGKeyGestureHold)" "SGFlag(SGKeyGestureHold, NO)"
mutate "hold follows the double tap's switch" "SGEnabled(SGKeyGestureHold)" "SGEnabled(@\"spotifyglass.gestures\")"
mutate "speed list reordered" "@[@1.5, @2, @3]" "@[@3, @2, @1.5]"
mutate "label without the times sign" "@\"%g×\"" "@\"%gx\""
mutate "announcement fixed at 2" "times speed\"), speed]" "times speed\"), 2.0]"
echo "all mutations killed"
