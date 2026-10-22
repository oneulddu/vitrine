#!/usr/bin/env python3
"""Runs the two ATSProbe bundles and checks what the shipped policy allows.

usage: check.py <build dir>            (build.sh calls this)
       check.py --self-test            (classifier regression, no probing)

The shipped bundle carries the IPA's own ATS keys merged with plist/liquid-glass.plist, exactly as
the pipeline injects them; the original bundle carries only the IPA's own keys. Everything runs
through the real URLSession of a bundled Mac app, so ATS itself makes the decision.

What an outcome proves: ATS decides before any connection, so "ATS-refused" means refused by policy
whatever the host is doing. An HTTP status means the policy allowed the address and the request
reached the server. A network error at an address that should have been refused is a real failure,
and a network error at an address that should have been allowed only shows it was not refused, so
that check is reported INCONCLUSIVE: it is not HTTP connectivity evidence. A probe that printed
nothing, printed something unreadable, or never answered is never taken as an allow.

Exit status: 0 every check passed and is decisive; 1 a check failed; 2 nothing failed but at least one
check was inconclusive, so the run is not an all-verified claim.
"""
import http.server
import json
import os
import subprocess
import sys
import threading

REFUSED, HTTP_200, HTTP_OTHER, NETWORK, EXPIRED, MALFORMED, MISSING = (
    "refused", "HTTP 200", "HTTP other", "network", "probe expired", "malformed", "missing")


def classify(outcome):
    """What a probe line says, or that it says nothing usable."""
    if not isinstance(outcome, str):
        return MISSING
    text = outcome.strip()
    if not text:
        return MALFORMED
    if text == "ATS-refused":
        return REFUSED
    if text == "probe-expired":
        return EXPIRED
    if text == "HTTP 200":
        return HTTP_200
    if text.startswith("HTTP ") and text[5:].isdigit() and 200 <= int(text[5:]) <= 599:
        return HTTP_OTHER
    domain, _, code = text.rpartition("/")
    if domain == "NSURLErrorDomain" and code.lstrip("-").isdigit():
        return NETWORK
    return MALFORMED


def evaluate(outcome, want):
    """('pass'|'fail'|'inconclusive', what the outcome was) for one expectation.

    want='refused': the address must be refused by policy. Anything else -- including no answer or
    an unreadable line -- fails, since a refused address answers deterministically.
    want='http-200': the local server must be reached.
    want='not-refused': the policy must admit the address. A network error only proves it was not
    refused, so it is inconclusive rather than an allow; refused is a failure."""
    kind = classify(outcome) if outcome is not None else MISSING
    if want == "refused":
        return ("pass" if kind == REFUSED else "fail"), kind
    if want == "http-200":
        return ("pass" if kind == HTTP_200 else "fail"), kind
    if want == "not-refused":
        if kind in (HTTP_200, HTTP_OTHER):
            return "pass", kind
        if kind == REFUSED:
            return "fail", kind
        if kind in (MALFORMED, MISSING):
            return "fail", kind
        return "inconclusive", kind
    raise ValueError(f"unknown expectation {want!r}")


def local_server(port=0):
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            body = json.dumps({"object": "list", "data": [{"id": "check-model"}]}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = http.server.HTTPServer(("0.0.0.0", port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def tailnet_ip():
    for command in (["tailscale", "ip", "-4"], ["/Applications/Tailscale.app/Contents/MacOS/Tailscale", "ip", "-4"]):
        try:
            out = subprocess.run(command, capture_output=True, text=True, timeout=5).stdout.split()
        except (OSError, subprocess.SubprocessError):
            continue
        for address in out:
            if address.startswith("100."):
                return address
    return None


def probe(bundle, urls):
    # One address per process: a refused address appears to warm a per-process ATS decision that can
    # then be applied to the next address asked for, which makes a single-process run of several
    # addresses order-dependent. A fresh process answers for its own address every time.
    outcomes = {}
    app = os.path.join(bundle, "ATSProbe.app")
    for url in urls:
        try:
            result = subprocess.run([os.path.join(app, "Contents", "MacOS", "probe"), url],
                                    capture_output=True, text=True, timeout=60)
        except (OSError, subprocess.SubprocessError) as problem:
            outcomes[url] = f"probe could not run: {problem}"
            continue
        lines = [line for line in result.stdout.strip().splitlines() if line.strip()]
        fields = lines[-1].split("\t") if lines else []
        if result.returncode != 0 or len(fields) != 2 or fields[0] != url:
            outcomes[url] = f"probe failed ({result.returncode}): {result.stdout.strip() or result.stderr.strip()}"
        else:
            outcomes[url] = fields[1]
    return outcomes


def main(argv):
    build = argv[1]
    server = local_server()
    port = server.server_address[1]
    host = tailnet_ip()
    rows, failures, inconclusive = [], [], []

    def check(bundle, url, want, why):
        outcome = probe(bundle, [url]).get(url)
        verdict, kind = evaluate(outcome, want)
        rows.append(f"{url}\t{outcome}\t{verdict}: {kind}\t{why}")
        if verdict == "fail":
            failures.append(f"{url}: {outcome} ({why}; wanted {want})")
        elif verdict == "inconclusive":
            inconclusive.append(f"{url}: {outcome} ({why}; not refused, but not HTTP evidence either)")

    shipped = os.path.join(build, "overlays")
    original = os.path.join(build, "original")

    # 1. Rejected addresses: ATS must refuse them, which it does before connecting.
    check(shipped, "http://100.63.255.255/", "refused", "one below the tailnet range")
    check(shipped, "http://100.128.0.0/", "refused", "one above the tailnet range")
    check(shipped, "http://8.8.8.8/", "refused", "public address, no exception")
    check(shipped, "http://example.com/", "refused", "public hostname, no exception")

    # 2. The same range without the exception: refused there is the regression baseline.
    for url in ("http://100.64.0.1/", "http://100.127.255.255/"):
        check(original, url, "refused", "refused without the exception (baseline)")

    # 3. The tailnet range admits plain HTTP. Refused is a failure; any other outcome is only
    #    reported as not-refused, never as proof of connectivity.
    check(shipped, "http://100.64.0.1/", "not-refused", "100.64.0.0/10 first address")
    check(shipped, "http://100.127.255.255/", "not-refused", "100.64.0.0/10 last address")

    # 4. Real HTTP over the policy: loopback, then this Mac's own Tailscale address, both served by
    #    the local /v1/models server. HTTP 200 here is the connectivity evidence.
    check(shipped, f"http://127.0.0.1:{port}/v1/models", "http-200", "loopback, local networking")
    if host:
        check(shipped, f"http://{host}:{port}/v1/models", "http-200", "this Mac's Tailscale address, plain HTTP")
    else:
        inconclusive.append("no Tailscale IPv4 address found: the HTTP 200 over the tailnet was not checked")

    print("\n".join(rows))
    for line in inconclusive:
        print(f"INCONCLUSIVE: {line}")
    if failures:
        print("ATS policy check FAILED:\n  " + "\n  ".join(failures), file=sys.stderr)
        return 1
    if inconclusive:
        print("ATS policy check INCOMPLETE: nothing failed, but the run is not all-verified.")
        return 2
    print("ATS policy: rejected addresses refused, tailnet range not refused, and plain HTTP 200 "
          "from the local server over both loopback and the Tailscale address")
    return 0


def self_test():
    """The classifier and every expectation, on the exact good and degenerate outcomes."""
    cases = [
        # (outcome, want, expected verdict)
        ("HTTP 200", "http-200", "pass"),
        ("HTTP 500", "http-200", "fail"),
        ("ATS-refused", "refused", "pass"),
        ("NSURLErrorDomain/-1001", "refused", "fail"),         # a refused address that answered otherwise
        ("HTTP 200", "refused", "fail"),
        ("probe-expired", "refused", "fail"),
        ("", "refused", "fail"),
        ("junk", "refused", "fail"),
        (None, "refused", "fail"),
        ("HTTP 200", "not-refused", "pass"),
        ("HTTP 204", "not-refused", "pass"),
        ("ATS-refused", "not-refused", "fail"),
        ("NSURLErrorDomain/-1001", "not-refused", "inconclusive"),
        ("NSURLErrorDomain/-1004", "not-refused", "inconclusive"),
        ("HTTP 0", "not-refused", "fail"),
        ("HTTP 999", "not-refused", "fail"),
        ("probe-expired", "not-refused", "inconclusive"),
        ("", "not-refused", "fail"),
        ("no answer", "not-refused", "fail"),
        (None, "not-refused", "fail"),
    ]
    for outcome, want, expected in cases:
        verdict, _ = evaluate(outcome, want)
        assert verdict == expected, f"{outcome!r} want={want}: {verdict}, expected {expected}"
        assert classify(outcome) != MISSING or outcome is None, f"{outcome!r} classified missing"

    # The reported values themselves, so a probe's sentinels cannot drift silently.
    assert classify("ATS-refused") == REFUSED
    assert classify("HTTP 200") == HTTP_200
    assert classify("HTTP 404") == HTTP_OTHER
    assert classify("HTTP 599") == HTTP_OTHER
    assert classify("NSURLErrorDomain/-1001") == NETWORK
    assert classify("probe-expired") == EXPIRED
    for bad in ("", "  ", "no answer", "HTTP ", "HTTP 0", "HTTP 999", "HTTP -1", "HTTP abc",
                "NSURLErrorDomain/x", "ok\tno"):
        assert classify(bad) == MALFORMED, bad
    assert classify(None) == MISSING

    # A run missing its baseline cannot pass: the expectation fails on the absent outcome.
    assert evaluate(None, "refused")[0] == "fail"
    print(f"ATS check self-test: {len(cases)} outcome cases and classifier sentinels passed")
    return 0


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        sys.exit(self_test())
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[3], file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv))
