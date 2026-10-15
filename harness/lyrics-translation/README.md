# Lyrics translation check

Run `harness/lyrics-translation/build.sh` from the repository, or `./build.sh` here. It compiles the
checkout's production sources into a Mac Catalyst binary, then runs offline with no simulator. By default the
replies are made up; no real lyrics or API keys are stored and no translation service is contacted.
An explicit `--bing-live` run, described below, contacts Bing.

The checks cover:

- Musixmatch's community translations matched onto copies of a song's lines by folded text, leaving
  the original lines untouched (`SGMusixmatchTranslatedLines`).
- Gemini's reply and reasons for failure (`SGGeminiTranslationsIn`): a blocked prompt, a recitation or
  safety stop, a different line count, the key and the limit.
- DeepL's language mapping, unknown tags, ordered translation arrays, missing fields, wrong types and
  oversized translations (`SGDeepLTargetLanguage`, `SGDeepLTranslationsIn`). The language allowlist
  follows [DeepL's text language table](https://developers.deepl.com/docs/getting-started/supported-languages).
- Batches that retain original indices, skip blank lines, stop at 50 texts for DeepL or 3500 UTF-16
  units including joining newlines for Google, and reject oversized lines or songs. Tests include
  the 51st line, exact character boundaries and non-Latin text (`SGLyricsTranslationBatches`).
- Google's language aliases, instrumental markers and bracketed tags, segment concatenation, LF and
  CRLF splitting, and mismatched counts that tell the caller to retry each line. Form tests include
  ampersands, plus signs, equals signs, percent signs, newlines, Korean and emoji
  (`SGGoogleTargetLanguage`, `SGGoogleKeepsLine`, `SGGoogleTranslationTextIn`,
  `SGGoogleTranslationLinesIn`, `SGGoogleTranslationForm`).
- Bing's language mapping, the HTML page's IG/IID/token tuple, missing markers, invalid numbers and
  types, default/minimum token lifetime, malformed or oversized translations, and trailing whitespace
  without dropping line boundaries or leading spaces. Its batches stop at 40 lines or 2800 UTF-16 units.
  Scripted transport exercises the production job: token refresh once, line-count fallback, embedded
  newlines, protected lines unchanged, percent encoding, increasing SFX, configuration reuse, memo
  reuse and invalidation on changed source text, opt-in checks, and a single completion on main.
- OpenAI-compatible replies as strict JSON arrays or single-value objects, with and without a JSON
  code fence. Wrong types, malformed fences, excessive sizes and mismatched counts fail. Base URLs
  accept HTTPS, or HTTP only for localhost, 127.0.0.1 and .local hosts, and reject credentials, query
  strings and fragments (`SGOpenAITranslationsIn`, `SGOpenAICompletionURL`). Requests follow the
  [Chat Completions format](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create).

Expected output:

```text
DeepL / Google / OpenAI: mapping, malformed replies, line counts, bounds, form encoding and URL checks passed
Bing: language, configuration, bounds, padded lines, token retry, fallback, opt-in, memo and main completion checks passed
lyrics translation: all checks passed
```

The new translators share the bounded transport in `DeepL.m`, so that file is linked alongside
`GoogleTranslate.m`, `BingTranslate.m` and `OpenAITranslate.m`. It receives at most 512 KiB per reply, uses ephemeral
sessions without disk caching, refuses redirects, and retries 429 up to three times with jittered
1/2/4-second backoff. Google, Bing and OpenAI-compatible services retry 5xx too. Google and Bing check their opt-in
before each attempt and batch. Each service keeps up to 32 successful song/language results in memory,
checks that the source text still matches, and completes on main. DeepL sends at most 50 texts and
16000 UTF-16 units per batch; Google rejects individual lines over 3500 units instead of truncating
or splitting their characters. Bing uses the same structure, with 40-line / 2800-unit batches and
its page configuration cached until 30 seconds before expiry. Whole inputs are limited to 2000 lines and 128000 UTF-16 units.

The harness compiles the network and settings code. DeepL's transport symbol is renamed in its
harness object so an offline wrapper can supply scripted Bing replies; the real transport remains
available for the live mode. `SGLyricsSourceRequest` is a harness stand-in to avoid linking the
unrelated lyrics-provider registry. Its live GET uses a private ephemeral session, no cookies or
credentials, a 2 MiB limit and no redirects, matching the production source transport's constraints.
The live POST uses the actual bounded translation transport from `DeepL.m`.

To make one live translation job with two made-up English sentences and a protected music marker:

```sh
harness/lyrics-translation/build.sh --bing-live
# Or, after building:
harness/lyrics-translation/build/check --bing-live
```

This mode checks a Korean result, the unchanged music marker and main-thread completion, and reports
GET/POST counts. It makes real requests only when explicitly invoked. No tokens or keys are printed.

Not exercised here: real token expiration, transport retry/backoff under 429/5xx, Keychain storage,
settings alerts, saved translations, or lyrics views taking up a result on the iPhone. Settings-page
and menu integration and localization table updates belong to the parent assignment. New visible
strings use SGL with English fallbacks; Korean text is supplied in the implementation handoff.
