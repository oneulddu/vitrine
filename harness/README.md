# Harnesses in CI

`.github/workflows/harness.yml` runs the offline macOS / Mac Catalyst checks on
`macos-latest`, on relevant pushes to `main` and `ci/harness`, pull requests,
and manual dispatch. Each named matrix job builds **and runs** its harness;
failure does not cancel the other jobs. Jobs have a 15-minute timeout.
No simulator, phone, Spotify installation, API credentials or visual review is
used. Only the two Logos hook checks use the existing setup-Theos action; its
caches contain build tools/output, never credentials or test data.

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
| `fluid-clip/build.sh` | Generated cover/video, decoded-frame and loop assertions. |
| `haptics/build.sh` | `build/track`: synthetic ISRC/protobuf/catalog assertions. |
| `head-gestures/build.sh` | Synthetic motion traces with expected gestures. |
| `listening-stats/build.sh` | Synthetic imports, calendar cases and 100k-row checks. |
| `local-files/build.sh` | Isolated metadata and imported LRC checks. |
| `lyrics/translation-check.sh` | Catalyst lyrics-menu assertions, not screenshots alone. |
| `lyrics-clip/build.sh` | Default synthetic still/animated clips with decode assertions. |
| `lyrics-sources/build.sh` | Offline provider/parser/language fixtures. |
| `lyrics-sources/state-build.sh` | Real keeper and concurrent source walk with fake replies. |
| `lyrics-translation/build.sh` | Default checks include `check-ai.m`; also `--auto-retry-only`. |
| `motion/build.sh` | Generated Canvas cuts and synthetic protobuf replies. |
| `now-playing/build.sh` | Logos setter hooks with system setter replaced, lyrics off/on. |
| `palette/build.sh` | Generated image with asserted edge/main colors. |
| `pitch/build.sh` | Synthetic sine pitch/speed assertions, no song argument. |
| `player/title-notification-check.sh` | Real Logos controller with offline notification fixtures. |
| `radio-modes/build.sh` | Foundation Spotify mocks, spoofing off/on. |
| `sing/build.sh` | `spatial`: model-free lead, spatial and decoder assertions. |
| `sleep-timer/build.sh` | Fake player and timer/fade assertions. |
| `spicy-lyrics/build.sh` | Offline parser, cache and retry fixtures. |
| `visualiser/build.sh` | Synthetic spectrum and PCM waveform assertions. |

## Excluded scripts

This inventory covers all 65 shell scripts, including the 26 included above.
Simulator checks are excluded even when they assert; visual-only simulator
scenarios are not promoted to CI by merely compiling them.

| Script | Reason |
| --- | --- |
| `addtab/build.sh` | iOS simulator UI. |
| `album/build.sh` | iOS simulator UI. |
| `appearance-page/build.sh` | iOS simulator UI. |
| `artist/build.sh` | iOS simulator UI. |
| `audio-effects-page/build.sh` | iOS simulator UI. |
| `audio-effects/build-sim.sh` | iOS simulator audio chain. |
| `clean-links/build-sim.sh` | iOS simulator share/pasteboard hooks. |
| `connect/build.sh` | Opens loopback sockets; excluded by the no-network requirement. |
| `driver/build.sh` | iOS simulator driver app. |
| `glass/build.sh` | iOS simulator visual rendering. |
| `haptics-page/build.sh` | iOS simulator UI. |
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
