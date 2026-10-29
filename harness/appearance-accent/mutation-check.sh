#!/bin/bash
# Each focused production mutation must fail its behavioral/performance check without launching a GUI.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources/Redesigned/Kit" && pwd)
OUT=$(mktemp -d /tmp/vitrine-accent-mutations.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
python3 - "$SRC" "$OUT" <<'PY'
from pathlib import Path
import sys
source, output = map(Path, sys.argv[1:])
mutations = [
    ("SGRAccentContext.m", "stock.m", "availableAtLaunch && requested", "requested"),
    ("SGRAccentContext.m", "reenable.m", "availableAtLaunch && requested", "SGRAccentSubstitutionEnabled() && requested"),
    ("SGRAccent.x", "SGRAccent.x", "    if (!sources && !existing[slot]) return;\n", ""),
    ("SGRAccent.x", "off-provenance.x",
     "static CGFloat tokenShade(CGFloat r, CGFloat g, CGFloat b) {\n",
     "static CGFloat tokenShade(CGFloat r, CGFloat g, CGFloat b) {\n    if (!SGRAccentSubstitutionEnabled()) return -1;\n"),
]
for filename, destination, before, after in mutations:
    text = (source / filename).read_text()
    if text.count(before) != 1:
        raise SystemExit(f"mutation target is not unique: {filename}")
    (output / destination).write_text(text.replace(before, after))
PY
if CONTEXT="$OUT/stock.m" bash "$HERE/check.sh" stock > "$OUT/stock.log" 2>&1; then
    printf 'FAIL: stock-launch mutation survived\n' >&2
    exit 1
fi
if CONTEXT="$OUT/reenable.m" bash "$HERE/check.sh" reenable > "$OUT/reenable.log" 2>&1; then
    printf 'FAIL: live re-enable mutation survived\n' >&2
    exit 1
fi
if ACCENT_HOOK="$OUT/SGRAccent.x" bash "$HERE/check.sh" animations > "$OUT/animations.log" 2>&1; then
    printf 'FAIL: animation metadata mutation survived\n' >&2
    exit 1
fi
if ACCENT_HOOK="$OUT/off-provenance.x" bash "$HERE/check.sh" reenable > "$OUT/off-provenance.log" 2>&1; then
    printf 'FAIL: off-interval provenance mutation survived\n' >&2
    exit 1
fi
python3 - "$OUT" <<'PY'
from pathlib import Path
import sys
output = Path(sys.argv[1])
for case, expected in [
    ("stock", "Automatic from stock waits for restart"),
    ("reenable", "accent launch restores Automatic live after switching to Spotify"),
    ("animations", "no-token animation setters write no metadata"),
    ("off-provenance", "colors assigned while stock recolor when Automatic returns"),
]:
    log = (output / f"{case}.log").read_text()
    if expected not in log:
        raise SystemExit(f"{case} failed for an unexpected reason:\n{log}")
    print(f"PASS: {case} mutation rejected: {expected}")
PY
