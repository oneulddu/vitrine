#!/usr/bin/env python3
"""Drive the app on the iPhone from the Mac: the phone driver of FLEX builds (Diagnostics/Driver.m).

    scripts/phone.py tree                              # the visible screen's view tree, as make trees records it
    scripts/phone.py state                             # now playing, the top controller, what is presented, menu up
    scripts/phone.py find --class UILabel              # every match with its index, frame (screen points), id, label, text
    scripts/phone.py tap --id X | --label X | --text X | --class C [--index N] | --at X,Y
    scripts/phone.py longpress --id X [--duration 1]
    scripts/phone.py swipe --from X,Y --to X,Y [--duration 0.2]     # or a view and --by DX,DY; a quick one flings
    scripts/phone.py swipe --id X --by 0,-300 --drag 1              # a slow drag held still before letting go
    scripts/phone.py scroll [--id X | --at X,Y] --by 0,400 [--animated 1]   # the page's list when no view is named
    scripts/phone.py type "some text"                  # into the first responder (tap a field first)
    scripts/phone.py player.open | player.close | player.more
    scripts/phone.py menu.pick "Sleep timer"
    scripts/phone.py play | pause | next
    scripts/phone.py seek 42 | seek --by -15            # to a position, or by an amount as Spotify's relative seeks do
    scripts/phone.py speed 1.5                         # playback speed, 1 when normal
    scripts/phone.py sing 1                            # Karaoke on (0 off)
    scripts/phone.py landscape 1                       # the redesign's landscape lyrics up (0 down), no turn needed
    scripts/phone.py lossless anchor --path P | lossless check | lossless stop   # a local FLAC in place of Spotify's sound
    scripts/phone.py tab 0 | tab Search
    scripts/phone.py settings.open
    scripts/phone.py settings.page "Appearance"
    scripts/phone.py pref --key spotifyglass.font --value 6     # a setting, as a whole number (--text for a string, --remove 1)
    scripts/phone.py wait --id X [--gone 1] [--timeout 5]
    scripts/phone.py wait --menu 1 [--gone 1]
    scripts/phone.py wait --log "system menu: the player's menu is up" --timeout 3
    scripts/phone.py log [--since N]                   # the app's last SGLog lines; each has a seq
    scripts/phone.py screenshot out.png [--scale 1]
    scripts/phone.py pip.frame out.png [--current X] [--next Y] [--credit Z]   # a PiP frame drawn to PNG, no PiP needed

Every command prints the app's JSON answer, {"ok": true, ...} or {"ok": false, "error": ...}, and exits 1
when it is not ok. --label and --text match whole and ignore case; --contains 1 matches a part. Points are
screen points, the frame `find` prints. A log wait looks at the lines since the last command that did
something began, so `player.more` then `wait --log ...` sees a line that came before the wait.
Private preference values are redacted in command output. Pref replies from older drivers without
privacy metadata are also redacted.

The server listens on the phone's loopback only, port 8085, so this goes through iproxy over USB: it uses
whatever already answers on 127.0.0.1:8085 (an iproxy left running, or the simulator, whose apps share the
Mac's loopback) and otherwise starts iproxy and leaves it running for the next call. PHONE_PORT changes the
port. For Tailscale, set PHONE_HOST to the phone's current Tailscale IP. PHONE_TOKEN supplies its
credential; without it, the script reads spotifyglass.driver.token over USB/loopback first, so the cable
path must be available. Credential discovery never prints the token. FLEX builds listen on the phone's
Tailscale address too, with authentication required. Needs a FLEX build (make install FLEX=1) open in
the foreground: iOS suspends it in the background.
"""
import base64
import http.client
import json
import os
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

PORT = int(os.environ.get("PHONE_PORT", "8085"))
# Tailscale destination. Authentication uses PHONE_TOKEN or reads the stored key through the cable;
# that lookup bypasses HOST so it never needs the credential it is trying to retrieve.
HOST = os.environ.get("PHONE_HOST")


def checked_token(value):
    if not isinstance(value, str) or len(value) != 32 or any(c not in "0123456789abcdef" for c in value):
        sys.exit("driver token must be exactly 32 lowercase hex characters; refresh the stored token or set a valid PHONE_TOKEN")
    return value


def token():
    if os.environ.get("PHONE_TOKEN"):
        return checked_token(os.environ["PHONE_TOKEN"])
    try:
        query = urllib.parse.urlencode({"key": "spotifyglass.driver.token"})
        answer = json.loads(fetch(f"pref?{query}", 20, loopback=True))
    except (SystemExit, OSError, ValueError):
        sys.exit("no PHONE_TOKEN and the USB/loopback token lookup failed: connect and trust the iPhone "
                 "with a FLEX build open in the foreground, or set PHONE_TOKEN")
    value = answer.get("now") if isinstance(answer, dict) and answer.get("ok") is True else None
    if not isinstance(value, str) or not value:
        sys.exit("USB/loopback did not return a stored driver token: open a current FLEX build, or set PHONE_TOKEN")
    return checked_token(value)
# The argument a command takes without a flag.
POSITIONAL = {"type": "text", "menu.pick": "title", "seek": "seconds", "speed": "arg", "sing": "arg", "lossless": "arg", "tab": "arg", "settings.page": "title"}


def port_open():
    try:
        with socket.create_connection(("127.0.0.1", PORT), timeout=0.5):
            return True
    except OSError:
        return False


def ensure_tunnel():
    if port_open():
        return
    if not shutil.which("iproxy"):
        sys.exit(f"nothing answers on 127.0.0.1:{PORT} and there is no iproxy (brew install libimobiledevice)")
    subprocess.Popen(["iproxy", f"{PORT}:{PORT}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    for _ in range(30):
        if port_open():
            return
        time.sleep(0.1)
    sys.exit(f"iproxy did not open 127.0.0.1:{PORT}: is the iPhone plugged in and trusted?")


def fetch(path, timeout, *, loopback=False):
    # The header the app asks of a driver command, which a web page on the phone cannot send.
    headers = {"X-Phone-Driver": "1"}
    try:
        if HOST and not loopback:
            headers["X-Phone-Token"] = token()
            url = f"http://{HOST}:{PORT}/{path}"
        else:
            ensure_tunnel()
            url = f"http://127.0.0.1:{PORT}/{path}"
        request = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.read().decode("utf-8")
    except urllib.error.HTTPError:
        sys.exit("the driver rejected the HTTP request; check the connection and credential")
    except (urllib.error.URLError, OSError, ValueError, http.client.HTTPException):
        sys.exit("the app did not answer; check USB/Tailscale and keep a FLEX build open in the foreground")


def parse(args):
    """`cmd --key value ... [positional]` into the command and its query items."""
    params, rest = {}, list(args)
    while rest:
        arg = rest.pop(0)
        if arg.startswith("--") and len(arg) > 2:
            key = arg[2:]
            params[key] = rest.pop(0) if rest and not rest[0].startswith("--") else "1"
        else:
            params.setdefault("arg", arg)
    return params


def run(argv):
    if not argv or argv[0] in ("-h", "--help", "help"):
        print(__doc__)
        return 0
    command, params = argv[0], parse(argv[1:])
    if command == "tree":
        print(fetch("tree", 15), end="")
        return 0
    out = None
    if command in ("screenshot", "pip.frame"):
        out = params.pop("arg", None)
        if not out:
            sys.exit(f"{command} takes the path to save the PNG to")
    if "arg" in params and command in POSITIONAL:
        params[POSITIONAL[command]] = params.pop("arg")
    timeout = float(params.get("timeout", 5)) + float(params.get("duration", 0)) + 15
    text = fetch(f"{urllib.parse.quote(command)}?{urllib.parse.urlencode(params, quote_via=urllib.parse.quote)}", timeout)
    try:
        answer = json.loads(text)
        if not isinstance(answer, dict):
            raise ValueError
    except ValueError:
        sys.exit("not a driver answer: use a FLEX build with the phone driver")
    if command == "pref" and answer.get("private") is not False and "now" in answer:
        # Privacy is decided by the app's central denylist. Older drivers without that metadata
        # are redacted too; token() consumes its raw loopback reply without using this output path.
        answer["now"] = "[redacted]"
    if out and answer.get("ok"):
        with open(out, "wb") as f:
            f.write(base64.b64decode(answer.pop("png")))
        answer["saved"] = os.path.abspath(out)
    print(json.dumps(answer, indent=1, ensure_ascii=False, sort_keys=True))
    return 0 if answer.get("ok") else 1


if __name__ == "__main__":
    sys.exit(run(sys.argv[1:]))
