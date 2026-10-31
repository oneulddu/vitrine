#!/bin/sh
# AutoMix's transitions in the redesigned player and the AutoMix page's preview (main.m's automix scenario,
# automix-scenario.m) in a simulator of its own, made for the run and deleted after it. Exits nonzero unless the
# scenario ends with "automix checks: n of n right -- PASS".
#     THEOS=$HOME/theos sh harness/player/automix-check.sh
# SRC=<tweak/Sources> builds other sources (automix-mutation-check.py). SHOTS=<dir> keeps a screenshot of each state
# the scenario names (automix: screenshot <name> now).
# What it exercises, which build.sh compiles (named here so scripts/harness-plan.py picks this harness for them):
#     tweak/Sources/Redesigned/Player/PlayerMix.x tweak/Sources/Redesigned/Player/PlayerControls.x
#     tweak/Sources/Redesigned/Player/PlayerArtwork.x tweak/Sources/Redesigned/Player/PlayerQueue.m
#     tweak/Sources/Shared/AutoMix/AutoMixSettings.m tweak/Sources/Shared/AutoMix/AutoMixPreview.m
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/player-automix.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
OUT="$WORK/build" sh "$HERE/build.sh" > "$WORK/build.log" 2>&1 || { cat "$WORK/build.log"; exit 1; }

TYPE=$(xcrun simctl list devicetypes | sed -n 's/.*(\(com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro\))$/\1/p' | head -1)
RUNTIME=$(xcrun simctl list runtimes available | sed -n 's/.* - \(com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]*\)$/\1/p' | tail -1)
UDID=$(xcrun simctl create "PlayerAutoMix-$$" "$TYPE" "$RUNTIME")
trap 'xcrun simctl shutdown "$UDID" >/dev/null 2>&1; xcrun simctl delete "$UDID" >/dev/null 2>&1; rm -rf "$WORK"' EXIT
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" > /dev/null
xcrun simctl install "$UDID" "$WORK/build/PlayerHarness.app"

# The scenario's log, line by line as it comes: each screenshot it names, and its verdict. It exits by itself in about
# a minute and a half; three are allowed.
python3 - "$UDID" "${SHOTS:-}" <<'PY'
import os, re, subprocess, sys, threading
udid, shots = sys.argv[1:3]
env = dict(os.environ, SIMCTL_CHILD_HARNESS_SCENARIO="automix")
launch = subprocess.Popen(["xcrun", "simctl", "launch", "--console-pty", udid, "com.vojta.playerharness"],
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
watchdog = threading.Timer(180, launch.kill)
watchdog.start()
verdict = None
for line in launch.stdout:
    if "[harness]" in line:
        print(line.rstrip(), flush=True)
    shot = re.search(r"automix: screenshot (\S+) now", line)
    if shot and shots:
        os.makedirs(shots, exist_ok=True)
        subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", os.path.join(shots, shot.group(1) + ".png")],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    result = re.search(r"automix checks: (\d+) of (\d+) right -- (PASS|FAIL)", line)
    if result:
        verdict = result.group(3)
    if verdict:
        break
watchdog.cancel()
launch.kill()
launch.wait()
if verdict != "PASS":
    print("FAILED: player automix (%s)" % (verdict or "no verdict in 180 s"), flush=True)
    sys.exit(1)
PY
