# Connection-test settings UI check

Run from the repository:

```sh
harness/connection-test-settings/check.sh
```

Builds the checkout's actual `ConnectionTestSettings.m`, `SGPage.m` and localization code with
Mac Catalyst UIKit. All generated artifacts stay in `.build/`; no simulator, API, credentials,
production preference writes or backend implementation is involved. A 15-second watchdog bounds the run.

The minimal `SGModRow` constructor preserves the production value/action/visibility callbacks.
`SGTestOpenAIConnection` and its cancellable handle are test doubles that retain callbacks so a
cancelled or superseded request can deliberately deliver a late answer. Host pages use real SGPage
lifecycle and UIWindow attachment. Presentation alone is intercepted to count requests and inspect
real UIAlertController titles, messages, appearance and actions without animation timing.

Checks cover:

- Two separate explicit rows (model-list check, sample translation); reading or redrawing them
  sends nothing, and no generation happens before an explicit tap.
- A missing key stays visible on both rows as `API key required` and produces an actionable
  configuration report instead of hiding the row.
- Explicit tap starts once; the running row says `Testing… · Cancel`, and a second tap cancels
  without sending another request. Cancelled late callbacks remain silent.
- Success/failure symbols and messages per row, dark result alerts with Copy details/Test Again/OK,
  cached-result taps. A model-list pass says only that the list was readable: it does not claim the
  key was verified or that every model can translate, and neither row claims a free request.
- Success is an evidenced fact, never merely a missing problem: the model row needs
  `report.models == Yes`, the translation row needs `report.translated == Yes`. A report with no
  problem but no such fact is shown as a failure.
- The translation success alert shows a fixed sentence only; no returned sample text, model, address
  or other server content is stored or displayed.
- Copied details are a safe `stage=… http=… sent=…` line only: never the key, Authorization, address,
  port, URL path, a model name, a free-form error domain, or a sample/lyric.
- A failed model check leaves the translation row's result alone and vice versa.
- Service and target-language notifications invalidate pending/cached results; late callbacks cannot
  overwrite a newer test. Unrelated generic notifications preserve pending and completed states.
- Results automatically request presentation only for an attached, topmost, uncovered page. Closing
  the page allows the bounded request to finish silently into the row cache; returning can inspect it
  without another request. This intentionally does not require cancellation on page close.

Observed result: **82/82 passed**, 18 fake backend starts and 5 cancellations.

This is UI callback/lifecycle coverage, not a full SGModPage rendering or pixel review. It checks the
presence of the alert's Copy details action, not its UIKit tap dispatch or pasteboard write. Real
transport, request, parser and redaction coverage belongs to
`harness/lyrics-translation/build.sh --connection-only` and is not rerun here.
