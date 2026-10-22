# App Transport Security check

Run `harness/ats/build.sh` from the repository (or `./build.sh` here). It needs the decrypted IPA in
`ipa/` and nothing else: no simulator, no iPhone, no API key.

## What this is, and what it is not

A **supported policy repair, not an established incident root cause.** Since iOS 17 ATS refuses HTTP
to a bare IP address even with `NSAllowsLocalNetworking` on, and Apple's `NSAllowsLocalNetworking` and
`NSExceptionDomains` pages say an individual IP address or CIDR range belongs in `NSExceptionDomains`.
Spotify's own Info.plist has `NSAllowsArbitraryLoads` off, `NSAllowsLocalNetworking` on and no IP
exception, while the OpenAI-compatible service accepts plain HTTP for a numeric Tailscale IPv4
address (`Shared/LyricsTranslation/OpenAITranslate.m`, `SGOpenAICompletionURL`). Adding
`100.64.0.0/10` to `NSExceptionDomains` is what that policy needs to admit the address the service
already accepts.

This harness does **not** reproduce the reported iPhone failure. The Lead ran both the original and
the overlays bundle against the actual `http://100.97.8.81:10100/v1/models`, and both printed HTTP
200: that server is the same Mac the probe runs on, so the probe never exercised a device-side
refusal. The iPhone's own error and whether this build recovers it are **unverified**. Nothing here
claims iOS is fixed from Apple's documentation; the device check is still owed: install a build
carrying this plist, then open Model list against the tailnet address and report what the row says
(`SGLyricsAIConnectionProblem` now distinguishes an ATS refusal from a timeout or a refused
connection).

The probe asks the system's URLSession for each address in a Mac app bundle; ATS decides before any
connection. An outcome only means what the checker reads it as:

- `ATS-refused` — refused by policy, whatever the host is doing.
- `HTTP <status>` — allowed by policy and answered by the server.
- any other network error — allowed by policy, but **no connectivity evidence**.
- `probe-expired`, empty, or unreadable — no evidence at all; never an allow.

## Checks

Two bundles are built from the IPA's own Info.plist: `overlays/` carries the ATS policy the pipeline
really injects (merged by `scripts/merge-overlay.py`), `original/` carries only Spotify's keys.
One probe process per address: a refused address otherwise appears to warm a per-process ATS
decision for the next address asked for.

1. **Rejected addresses must be refused**: one below (`100.63.255.255`) and one above
   (`100.128.0.0`) the tailnet range, a public address and a public hostname. Anything else,
   including no answer, fails: a refused address answers deterministically.
2. **Regression baseline, always run**: `100.64.0.1` and `100.127.255.255` must be refused in the
   bundle without the exception. There is no way to skip it, and a missing outcome fails.
3. **The tailnet range is not refused**: the first and last addresses of `100.64.0.0/10`. Refused
   fails; an HTTP status passes; a network error there is reported **INCONCLUSIVE**, not as
   connectivity proof.
4. **Real HTTP over the policy**: the local `/v1/models` server, reached over loopback and over this
   Mac's own Tailscale address, must answer HTTP 200.

Exit status `0` means every check passed and was decisive; `1` means a check failed; `2` means
nothing failed but something was inconclusive, and the run is not an all-verified claim.

`python3 harness/ats/check.py --self-test` (run by the build) exercises the classifier on the exact
good and degenerate outcomes: valid HTTP and ATS lines pass, a timeout or expired probe at an address
wanted not-refused is inconclusive, and an expired probe, empty or malformed line, or missing
baseline fails.

`scripts/merge-overlay.py --self-test` (also run by the build) checks the merge itself: an existing
domain dictionary is kept exactly as Spotify set it and never relaxed, `NSAllowsArbitraryLoads` stays
off, `NSAllowsLocalNetworking` stays on, and only `100.64.0.0/10` is added.
