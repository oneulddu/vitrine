# Connection-test settings UI check

Run from the repository:

```sh
harness/connection-test-settings/check.sh
```

Builds the checkout's actual `ConnectionTestSettings.m`, `SGPage.m` and localization code with
Mac Catalyst UIKit. All generated artifacts stay in `.build/`; no simulator, API, credentials,
production preference writes or backend implementation is involved. A 15-second watchdog bounds the run.

The minimal `SGModRow` constructor preserves the production value/action/visibility callbacks.
`SGTestOpenAITranslation` and its cancellable handle are test doubles that retain callbacks so a
cancelled or superseded request can deliberately deliver a late answer. Host pages use real SGPage
lifecycle and UIWindow attachment. Presentation alone is intercepted to count requests and inspect
real UIAlertController titles, messages, appearance and actions without animation timing.

Checks cover:

- Row creation, repeated value reads and redraws send nothing; missing key hides and guards the action.
- Explicit tap starts once; the running row says `Testing… · Cancel`, and a second tap cancels without
  sending another request. Cancelled late callbacks remain silent.
- Success/failure symbols and messages, dark result alerts, Test Again/OK actions, cached-result taps,
  empty failure fallback, nil handles and synchronous completion.
- Service and target-language notifications invalidate pending/cached results; late callbacks cannot
  overwrite a newer test. Unrelated generic notifications preserve pending and completed states.
- Results automatically request presentation only for an attached, topmost, uncovered page. Closing
  the page allows the bounded request to finish silently into the row cache; returning can inspect it
  without another request. This intentionally does not require cancellation on page close.

Observed result: **58/58 passed**, 13 fake backend starts and 3 cancellations.

This is UI callback/lifecycle coverage, not a full SGModPage rendering or pixel review. It checks the
presence of the alert's Test Again action, not its UIKit tap dispatch. Real transport/request/parser
coverage belongs to `harness/lyrics-translation/build.sh --connection-only` and is not rerun here.
