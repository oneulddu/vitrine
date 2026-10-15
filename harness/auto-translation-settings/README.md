# Automatic translation settings smoke

Run on an Apple Silicon Mac with the Xcode macOS SDK:

```sh
sh harness/auto-translation-settings/check.sh
```

Compiles the complete production `Redesigned/Lyrics/AutoTranslationSettings.m`,
`Settings/SGPage.m`, and `Core/SGLocalize.m`. Runs `UIApplicationMain` with real
Mac Catalyst UIKit; no simulator, external requests, API keys, or Git operations.
Build products and the test app stay in `.build/`. A 15-second launch watchdog
fails the process instead of leaving an unfinished run. English strings are used.

The smoke loads the actual order controller's view and executes its table data
source/delegate methods. It verifies:

- The switch's production `changed` callback invalidates automatic settings before
  enabling Show Translation. Switching off preserves both shown and hidden states.
- The order row waits on the automatic switch and reports the first available
  service, including a changed first service and the none-ready case.
- All eight services remain in stable order despite availability, with destination
  notes, all unavailable-state reasons, ready/unavailable colors, and reorder-only
  editing behavior.
- The real SGPage lifecycle supplies dark appearance; the order page creates and
  sizes its footer and supplies its header.
- Moving last to first forwards the exact order once to
  `SGRSetAutoTranslationOrder`, updates the current page and summary, and survives
  opening a fresh page. Moving first to last preserves every service.

## Boundaries

`SGModRow` and its two constructors are minimal stand-ins that retain the actual
production blocks. Style helpers use real UIKit cells and labels with minimal
formatting. Provider readiness, selected language, settings-change notifications,
Show Translation, and order get/set functions are deterministic test doubles.
The order setter records a copied in-memory array: this proves persistence-boundary
wiring and a fresh page reading that saved value, **not** production disk persistence
or order validation. No settings or fallback algorithm is copied into the harness.

The full SGModPage renderer (including its UISwitch event and disabled-row behavior),
App/Pages.m composition, production AutoTranslation.m runtime/fallback chain,
Spotify navigation integration, localization resources, drag gesture synthesis,
and pixel styling are outside this smoke. The parent's integration tests cover
runtime and order validation. This harness invokes UIKit's reorder delegate method
directly; it does not simulate a mouse drag. UIKit may interpose a table delegate
proxy, so the test checks real dispatch rather than pointer identity.

Verified: **76/76 assertions passed** on Mac Catalyst. An initial harness assertion
required controller/delegate pointer identity and failed; replacing that assumption
with actual table dispatch checks passed without production changes.
