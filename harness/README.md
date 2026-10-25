# Harnesses in CI

`.github/workflows/harness.yml` runs the offline macOS / Mac Catalyst checks on
`macos-latest`, on relevant pushes to `main` and `ci/harness`, pull requests,
manual dispatch, and a weekly schedule (Monday 03:00 UTC). Each harness builds
**and runs** its checks; failure does not cancel the other jobs.

CI has two jobs. `plan` (ubuntu) reads the changed files and asks
`scripts/harness-plan.py` which harnesses a change needs: a change selects a
harness when it touches `harness/<dir>/` or any file that harness's build
scripts and sources reach — every repo path named in a build/check script
(`-I ../autoeq/shim`, `VENDOR=../../vendor/audio`, `$SRC/...`), every file
under such a directory, plus transitive quoted imports. A new directory a
build script starts using is picked up without editing the script. Every harness runs when the event is `workflow_dispatch` or
`schedule`, when the changed list cannot be determined (new branch, force push,
shallow history), when a change touches `.github/`,
`scripts/harness-plan.py` or `tweak/Makefile`, or when a changed path is no longer
in the checkout (a deletion, or a rename's old name: the diff is taken with
`--no-renames`), since a harness may still use it. A harness with no tweak
dependency is always selected, with a warning. The selected harnesses are
packed into at most five shards (all Logos/Theos harnesses in one) and run as
`Harnesses <shard>` jobs with a 45-minute timeout. Only that Theos shard uses
the setup-Theos action; its caches contain build tools/output, never
credentials or test data.

Locally, the same script explains and runs selections from the repo root:

```sh
python3 scripts/harness-plan.py explain tweak/Sources/Shared/LockScreenLyrics/SGLyricsClip.m
python3 scripts/harness-plan.py run --names "Pitch" "Palette"
```

`plan --changed-from <file|->` prints the selection, shards and matrix JSON.
No simulator, phone, Spotify installation, API credentials or visual review is
used.

Run the commands in the workflow locally on an Apple Silicon Mac with Xcode.
The individual READMEs describe assertions and boundaries. Image/video output
is included only when the executable also checks the result and fails nonzero.
An offline fixture does not establish live-service or device compatibility.

## Included scripts and modes

All paths below are relative to `harness/`. Build-only scripts are followed by
their check executable in the workflow.

| Script | Mode / reason |
| --- | --- |
| `album-credits/build.sh` | Artist-credit matching assertions. |
| `audio-effects/build.sh` | `route` and `presets`: isolated settings and preset-file assertions. |
| `auto-translation-settings/check.sh` | Real Catalyst settings callbacks with fake providers. |
| `autoeq/build.sh` | Default offline index/preset fixtures, not `online`. |
| `clean-links/build.sh` | Pure URL-cleaning assertions. |
| `connection-test-settings/check.sh` | Catalyst lifecycle assertions with a fake backend. |
| `driver/auth-check.sh` | Foundation driver-token rotation, header and diagnostic-redaction checks; runs with `driver/phone-check.py`. |
| `driver/command-check.sh` | Driver command classification and log-cursor sequence with the real log buffer. |
| `fluid-clip/build.sh` | Generated cover/video, decoded-frame and loop assertions. |
| `haptics/build.sh` | `build/track`: synthetic ISRC/protobuf/catalog assertions. |
| `head-gestures/build.sh` | Synthetic motion traces with expected gestures. |
| `listening-stats/build.sh` | Synthetic imports, calendar cases and 100k-row checks. |
| `local-files/build.sh` | Isolated metadata and imported LRC checks. |
| `lyrics/translation-check.sh` | Catalyst lyrics-menu assertions, not screenshots alone. |
| `lyrics-clip/build.sh` | Default synthetic still/animated clips with decode assertions. |
| `lyrics-pip/build.sh` | Catalyst PiP text decision (`LyricsPiPText.m`) for synthetic lines and positions, plus frame fitting checks (`LyricsPiPFrame.m`) and sample frame PNGs. |
| `lyrics-sources/build.sh` | Offline provider/parser/language fixtures. |
| `lyrics-sources/state-build.sh` | Real keeper and concurrent source walk with fake replies. |
| `lyrics-store/build.sh` | Foundation codec, isolated disk reads/writes/deletion, and oldest-first count/byte pruning; run `lyrics-store/build/lyrics-store` after building. |
| `lyrics-translation/build.sh` | Default checks include `check-ai.m`; also `--auto-retry-only`. |
| `lyrics-translation/ondevice-kept-check.sh` | Catalyst Swift check: on-device translation keeps target-language lines as completed results. |
| `motion/build.sh` | Generated Canvas cuts and synthetic protobuf replies. |
| `now-playing/build.sh` | Logos setter hooks with system setter replaced, lyrics off/on. |
| `palette/build.sh` | Generated image with asserted edge/main colors. |
| `palette/field-check.sh` | Catalyst player field palette requests across mode changes and stale replies. |
| `pitch/build.sh` | Synthetic sine pitch/speed assertions, no song argument. |
| `player/title-notification-check.sh` | Real Logos controller with offline notification fixtures. |
| `radio-modes/build.sh` | Foundation Spotify mocks, spoofing off/on. |
| `sing/build.sh` | `spatial`: model-free lead, spatial and decoder assertions. |
| `sleep-timer/build.sh` | Fake player and timer/fade assertions. |
| `spicy-lyrics/build.sh` | Offline parser, cache and retry fixtures. |
| `update/offline-check.sh` | Catalyst cached-release selection, no network. |
| `visualiser/build.sh` | Synthetic spectrum and PCM waveform assertions. |

## Excluded scripts

This inventory covers all 74 shell scripts, including the 32 included above.
Simulator checks are excluded even when they assert; visual-only simulator
scenarios are not promoted to CI by merely compiling them.

| Script | Reason |
| --- | --- |
| `addtab/build.sh` | iOS simulator UI. |
| `album/build.sh` | iOS simulator UI. |
| `appearance-page/build.sh` | iOS simulator UI. |
| `artist/build.sh` | iOS simulator UI. |
| `audio-effects-page/build.sh` | iOS simulator UI. |
| `audio-effects/build-import.sh` | iOS simulator import page. |
| `audio-effects/build-output.sh` | iOS simulator output control and render gate. |
| `audio-effects/build-sim.sh` | iOS simulator audio chain. |
| `clean-links/build-sim.sh` | iOS simulator share/pasteboard hooks. |
| `connect/build.sh` | Opens loopback sockets; excluded by the no-network requirement. |
| `driver/build.sh` | iOS simulator driver app. |
| `glass/build.sh` | iOS simulator visual rendering. |
| `haptics-page/build.sh` | iOS simulator UI. |
| `home-tiles/build.sh` | iOS simulator UI. |
| `haptics/build-sim.sh` | iOS simulator audio/haptics hooks. |
| `head-gestures/sim/build.sh` | iOS simulator hooks and teaching UI. |
| `launch/build.sh` | Requires an untracked flag table extracted from a Spotify IPA. |
| `library/build.sh` | iOS simulator UI. |
| `listening-stats/build-sim.sh` | iOS simulator UI. |
| `live-activity-page/build.sh` | iOS simulator UI. |
| `local-files/lyrics/build.sh` | iOS simulator lyrics UI. |
| `local-files/sim/build-sim.sh` | iOS simulator editor and screenshots. |
| `lossless/build.sh` | iOS simulator decoder probe. |
| `lossless/handoff-build.sh` | iOS simulator audio chain. |
| `lyrics/build.sh` | iOS simulator lyrics UI. |
| `lyrics-page/build.sh` | iOS simulator settings UI. |
| `menu/build.sh` | iOS simulator UI. |
| `mod-settings/build.sh` | iOS simulator settings UI. |
| `morph/build.sh` | iOS simulator visual rendering. |
| `native-player/build.sh` | iOS simulator UI. |
| `onboarding/build.sh` | iOS simulator UI; also generates product release notes. |
| `player/build.sh` | iOS simulator player UI. |
| `playlist/build.sh` | iOS simulator UI. |
| `shortcuts/build.sh` | iOS simulator App Intents. |
| `sing/build-sim.sh` | iOS simulator audio chain and external model/voice. |
| `sing/button/build.sh` | iOS simulator mic-button UI. |
| `sing/download/build.sh` | Downloads the model over the network. |
| `spatial-page/build.sh` | iOS simulator UI. |
| `speed/build.sh` | iOS simulator audio chain. |
| `system-menu/build.sh` | iOS simulator UI. |
| `tabbar/build.sh` | iOS simulator UI. |
| `update/build.sh` | iOS simulator and live GitHub requests. |

Excluded modes of otherwise included scripts: AutoEq `online` and translation
`--bing-live` contact services; full Sing needs a downloaded model and voice;
the audio-effects engine and haptics analyzer need external song/scoring inputs.
Optional user-supplied images, songs, saved provider replies and videos are not
used. Lyrics clips' `motion` scenarios require additional video/FFmpeg fixtures;
the default clip assertions remain enabled.
