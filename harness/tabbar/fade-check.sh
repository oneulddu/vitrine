#!/bin/sh
# The fade under the bars (README, fade-check.sh) in an iOS simulator of the run's own, made for the run and deleted
# after it. Exits nonzero on the first failed check; screenshots go to $OUT/png.
#     THEOS=$HOME/theos OUT=/tmp/<dir> ./fade-check.sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT=${OUT:-$HERE/build}
OUT=$OUT sh "$HERE/build.sh"
mkdir -p "$OUT/png"

TYPE=$(xcrun simctl list devicetypes | sed -n 's/.*(\(com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro\))$/\1/p' | head -1)
RUNTIME=$(xcrun simctl list runtimes available | sed -n 's/.* - \(com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]*\)$/\1/p' | tail -1)
UDID=$(xcrun simctl create "TabBarHarness-$$" "$TYPE" "$RUNTIME")
trap 'xcrun simctl shutdown "$UDID" >/dev/null 2>&1; xcrun simctl delete "$UDID" >/dev/null 2>&1' EXIT
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" >/dev/null
xcrun simctl install "$UDID" "$OUT/TabBarHarness.app"

launch() {
    xcrun simctl launch --console-pty --terminate-running-process "$UDID" com.vojta.tabbarharness "$@" > "$OUT/run.log" 2>&1 || true
    cat "$OUT/run.log"
}

# A launch that ends itself: the line it must print.
run() {
    expected=$1
    shift
    launch "$@"
    grep -q "$expected" "$OUT/run.log" || { echo "FAILED: $*"; exit 1; }
}

# A launch that holds what it checked for a while and then ends itself: `name:seconds` pairs, each screenshot taken
# that long after the launch, then the line it must print.
shoot() {
    expected=$1
    shots=$2
    shift 2
    launch "$@" &
    pid=$!
    start=0
    for shot in $shots; do
        at=${shot#*:}
        sleep $((at - start))
        start=$at
        xcrun simctl io "$UDID" screenshot "$OUT/png/${shot%%:*}.png" >/dev/null
    done
    wait "$pid" || true
    grep -q "$expected" "$OUT/run.log" || { echo "FAILED: $*"; exit 1; }
}

run "PASS all fade" fade toggle
run "PASS all fade" fade toggle split
shoot "PASS fade: one fade" "fade-on:3" fade
shoot "PASS fade off: no fade" "fade-off:3" fade off
shoot "PASS fade mini: one fade" "fade-mini:3" fade mini
shoot "PASS all navsettings" "navsettings-on:3 navsettings-off:6" navsettings
echo "PASS tab bar fade checks; pictures in $OUT/png"
