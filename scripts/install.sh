#!/usr/bin/env bash
# Signs an IPA, or an app folder, with your own certificate and installs it on the paired iPhone, over USB
# or the network, through Xcode's devicectl.
#
#   scripts/install.sh out/<name>.ipa
#   scripts/install.sh out/quick/Payload/Spotify.app    # signed in place; scripts/quick.sh does this
#
# Put the certificate details in .signing.env (gitignored):
#   SIGN_P12=/path/to/cert.p12
#   SIGN_PROFILE=/path/to/profile.mobileprovision
#   SIGN_P12_PASSWORD=...
# With more than one iPhone paired, name the one to install to in .phone.env (gitignored, see
# .phone.env.example) as PHONE_UDID, or export PHONE_UDID for a single run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$ROOT/.signing.env" ] && . "$ROOT/.signing.env"
# .phone.env also holds your phone's Tailscale address and bundle id for scripts/phone.py, and a
# PHONE_UDID already exported here wins over the file.
_exported_udid="${PHONE_UDID-}"
[ -f "$ROOT/.phone.env" ] && . "$ROOT/.phone.env"
# A copy of .phone.env.example keeps the comment after the value; only the UDID before it counts.
PHONE_UDID="${_exported_udid:-${PHONE_UDID-}}"
PHONE_UDID="$(printf '%s' "${PHONE_UDID%%#*}" | tr -d '[:space:]')"
unset _exported_udid
cd "$ROOT"
: "${SIGN_P12:?set SIGN_P12 in .signing.env}" "${SIGN_PROFILE:?set SIGN_PROFILE in .signing.env}" "${SIGN_P12_PASSWORD:?set SIGN_P12_PASSWORD in .signing.env}"

IN="${1:?usage: $0 <ipa or .app folder>}"
# A folder is signed where it is, and zsign then re-signs only what changed since its last signing.
if [ -d "$IN" ]; then SIGNED="$IN"; else SIGNED="${IN%.ipa}-signed.ipa"; fi

command -v zsign >/dev/null || { echo "missing zsign -> brew install zsign" >&2; exit 1; }

# The bundle id has to equal the App ID of the profile. iOS may well install a mismatched pair, but
# MediaRemote launches the now playing app by its application-identifier entitlement rather than by
# CFBundleIdentifier, so tapping the lock screen card then asks for a bundle that does not exist and
# nothing opens. A wildcard App ID needs no rewrite: the entitlement takes the IPA's own bundle id.
PROFILE_PLIST="$(mktemp)"
security cms -D -i "$SIGN_PROFILE" > "$PROFILE_PLIST" 2>/dev/null
APP_ID="$(plutil -extract Entitlements.application-identifier raw -o - "$PROFILE_PLIST" 2>/dev/null || true)"
rm -f "$PROFILE_PLIST"
APP_ID="${APP_ID#*.}"

sign() {  # sign [bundle id]
  echo "==> signing${1:+ as $1}"
  if [ -d "$IN" ]; then
    zsign -k "$SIGN_P12" -p "$SIGN_P12_PASSWORD" -m "$SIGN_PROFILE" ${1:+-b "$1"} "$IN" >/dev/null
  else
    zsign -k "$SIGN_P12" -p "$SIGN_P12_PASSWORD" -m "$SIGN_PROFILE" ${1:+-b "$1"} -z 1 -o "$SIGNED" "$IN" >/dev/null
  fi
}

if [ -n "$APP_ID" ] && [ "$APP_ID" != "*" ]; then sign "$APP_ID"; else sign; fi
# devicectl promises its table only to humans; scripts read the JSON, which it keeps stable.
# One tab separated line per paired, physical iPhone: hardware UDID, marketing name, and its tunnel state,
# which reads "connected" over USB and "disconnected" when the phone is only paired, over the network.
phone_candidates() {  # json file
  python3 - "$1" <<'PY'
import json, sys
for device in json.load(open(sys.argv[1]))["result"]["devices"]:
    connection = device.get("connectionProperties") or {}
    hardware = device.get("hardwareProperties") or {}
    if connection.get("pairingState") != "paired" or connection.get("tunnelState") == "unavailable":
        continue
    if hardware.get("reality") != "physical" or hardware.get("deviceType") != "iPhone":
        continue
    if not hardware.get("udid"):
        continue
    print("\t".join([hardware["udid"], hardware.get("marketingName") or "iPhone",
                     connection.get("tunnelState") or "disconnected"]))
PY
}

# The phone to install to, as its hardware UDID: devicectl takes that one form for install, device info
# apps and device info processes alike.
phone() {
  local list candidates count
  if [ -n "$PHONE_UDID" ]; then printf '%s\n' "$PHONE_UDID"; return 0; fi
  list="$(mktemp)"
  xcrun devicectl list devices --json-output "$list" >/dev/null 2>&1 || { rm -f "$list"; return 0; }
  candidates="$(phone_candidates "$list")" || candidates=""
  rm -f "$list"
  count="$(printf '%s' "$candidates" | grep -c . || true)"
  case "$count" in
    0) return 0 ;;
    1) printf '%s\n' "$candidates" | cut -f1; return 0 ;;
  esac
  echo "more than one iPhone is paired; set PHONE_UDID in .phone.env to the one to install to:" >&2
  printf '%s\n' "$candidates" | awk -F'\t' '{ printf "  PHONE_UDID=%s  %s (%s)\n", $1, $2, $3 }' >&2
  return 1
}

# An install waits on the app while it runs, so a copy already on the phone is quit first.
quit_app() {
  [ -n "$APP_ID" ] && [ "$APP_ID" != "*" ] || return 0
  local udid="$UDID" apps procs pid
  apps="$(mktemp)"; procs="$(mktemp)"
  xcrun devicectl device info apps --device "$udid" --bundle-id "$APP_ID" --json-output "$apps" >/dev/null 2>&1 || true
  xcrun devicectl device info processes --device "$udid" --json-output "$procs" >/dev/null 2>&1 || true
  pid="$(python3 - "$apps" "$procs" <<'PY' 2>/dev/null || true
import json, sys
apps = json.load(open(sys.argv[1]))["result"]["apps"]
if apps:
    for p in json.load(open(sys.argv[2]))["result"]["runningProcesses"]:
        if p.get("executable", "").startswith(apps[0]["url"]):
            print(p["processIdentifier"])
            break
PY
)"
  rm -f "$apps" "$procs"
  [ -n "$pid" ] || return 0
  echo "==> quitting the running app ($pid)"
  xcrun devicectl device process terminate --device "$udid" --pid "$pid" >/dev/null 2>&1 || true
}

UDID="$(phone)" || exit 1
[ -n "$UDID" ] || { echo "no paired iPhone over USB or the network" >&2; exit 1; }
quit_app
echo "==> installing $SIGNED to $UDID"
out="$(xcrun devicectl device install app --device "$UDID" "$SIGNED" 2>&1)" || { printf '%s\n' "$out" | grep -iE "error|reason|description" | head -5 >&2; exit 1; }
printf '%s\n' "$out" | grep -E "installationURL" | tail -1
