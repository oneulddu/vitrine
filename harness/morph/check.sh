#!/bin/sh
# Build and run on an isolated simulator; neither an existing build nor a phone is touched.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
export THEOS=${THEOS:-$HOME/theos}
OUT=$(mktemp -d "${TMPDIR:-/tmp}/vitrine-morph-check.XXXXXX")
DEVICE=
cleanup() {
    status=$?
    cleanup_status=0
    if [ -n "$DEVICE" ]; then
        xcrun simctl shutdown "$DEVICE" || cleanup_status=$?
        xcrun simctl delete "$DEVICE" || cleanup_status=$?
    fi
    xcrun simctl shutdown all || cleanup_status=$?
    osascript -e 'tell application "Simulator" to quit' || cleanup_status=$?
    rm -rf "$OUT" || cleanup_status=$?
    if [ "$status" -ne 0 ]; then exit "$status"; fi
    exit "$cleanup_status"
}
trap cleanup EXIT
export MORPH_OUT="$OUT/normal" MORPH_UNSUPPORTED_OWNER=0
sh "$ROOT/harness/morph/build.sh"
DEVICE=$(xcrun simctl create "MorphClose-$$" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-5)
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl install "$DEVICE" "$MORPH_OUT/MorphHarness.app"
run_case() {
python3 - "$DEVICE" "$1" "${2:-}" <<'PY'
import os, subprocess, sys
env = dict(os.environ, SIMCTL_CHILD_MORPH_CHECK='1', SIMCTL_CHILD_MORPH_MUSIC=sys.argv[2])
result = subprocess.run(['xcrun', 'simctl', 'launch', '--console', sys.argv[1], 'com.vojta.morphharness'],
                        env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
print(result.stdout, flush=True)
expected_failure = sys.argv[3]
if expected_failure:
    if '[harness] FAIL' not in result.stdout or expected_failure not in result.stdout:
        sys.exit('mutation did not fail the intended contract: ' + expected_failure)
    print('[morph] PASS mutation rejected: ' + expected_failure + '; production source unchanged')
elif '[morph] PASS' not in result.stdout or '[harness] FAIL' in result.stdout:
    sys.exit('compact checks failed, musicClose=' + sys.argv[2])
PY
}
run_case 1
run_case 0
export MORPH_OUT="$OUT/unsupported" MORPH_UNSUPPORTED_OWNER=1
sh "$ROOT/harness/morph/build.sh"
xcrun simctl install "$DEVICE" "$MORPH_OUT/MorphHarness.app"
run_case 1
if [ "${1:-}" = "--mutation" ]; then
    python3 - "$ROOT" "$OUT" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1], 'tweak/Sources/Redesigned/Player/PlayerMorph.x').read_text()
mutations = {
    'geometry': ('CGFloat side = ramp(0.70, 1, p)', 'CGFloat side = ramp(0, 1, p)'),
    'owner': ('{"overlayView", "npbSnapshotView", "tabBarSnapshotView"}',
              '{"npbSnapshotView", "tabBarSnapshotView"}'),
}
for name, (before, after) in mutations.items():
    if source.count(before) != 1:
        sys.exit('mutation target is not unique: ' + name)
    Path(sys.argv[2], 'PlayerMorph-' + name + '.x').write_text(source.replace(before, after))
PY
    for mutation in geometry owner; do
        if [ "$mutation" = geometry ]; then
            MORPH_UNSUPPORTED_OWNER=0
            expected_failure="frozen p=0.55 left"
        else
            MORPH_UNSUPPORTED_OWNER=1
            expected_failure="unsupported owner duration"
        fi
        export MORPH_OUT="$OUT/mutated-$mutation" MORPH_SOURCE="$OUT/PlayerMorph-$mutation.x"
        sh "$ROOT/harness/morph/build.sh"
        xcrun simctl install "$DEVICE" "$MORPH_OUT/MorphHarness.app"
        run_case 1 "$expected_failure"
    done
fi
