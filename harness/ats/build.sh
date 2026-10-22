#!/bin/sh
# build.sh: builds harness/ats/probe.m into two Mac app bundles and checks what App Transport
# Security does with each address through a real bundled URLSession. One bundle carries the ATS
# policy the IPA build really ships (the IPA's own Info.plist with plist/liquid-glass.plist merged
# in, as scripts/pipeline.sh injects it); the other carries only the IPA's own keys, to show the
# fix is what changes the outcome. No simulator and no iPhone are needed; the decrypted IPA in ipa/
# supplies Spotify's own Info.plist.
#
#   harness/ats/build.sh          all checks
#
# ATS decides before a connection, so NSURLErrorAppTransportSecurityRequiresSecureConnection means
# refused by policy whatever the host is doing. Any other answer only means that address was not
# refused: an HTTP status is connectivity evidence, a network error is not, and a probe that never
# answered (probe-expired) is no evidence at all. check.py reports the last two honestly instead of
# counting them as allows.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
BUILD="$HERE/build"
IPA=${IPA:-$(ls "$ROOT"/ipa/*.ipa 2>/dev/null | head -1)}
[ -n "$IPA" ] || { echo "no decrypted IPA: put one in ipa/ or pass IPA=path.ipa" >&2; exit 1; }

APP_DIR=$(unzip -Z1 "$IPA" | grep -oE '^Payload/[^/]+\.app/' | sort -u | head -1)
[ -n "$APP_DIR" ] || { echo "no Payload/*.app in $IPA" >&2; exit 1; }

mkdir -p "$BUILD"
xcrun -sdk macosx clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation "$HERE/probe.m" -o "$BUILD/probe"

unzip -p "$IPA" "${APP_DIR}Info.plist" > "$BUILD/app-info.plist"
python3 -B "$ROOT/scripts/merge-overlay.py" --self-test
python3 -B "$ROOT/scripts/merge-overlay.py" "$ROOT/plist/liquid-glass.plist" "$BUILD/app-info.plist" "$BUILD/merged.plist"
python3 -B "$HERE/check.py" --self-test
python3 -B "$HERE/make-bundles.py" "$BUILD" "$BUILD/probe"

exec python3 -B "$HERE/check.py" "$BUILD"
