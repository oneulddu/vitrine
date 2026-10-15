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
- Claude's joined text parts, JSON fences, mismatched counts, malformed and oversized content, token
  exhaustion and HTTP/network errors, including 400's error message and 529. The request uses
  `claude-sonnet-5` by default, the Messages API headers, 8192 output tokens and the translation instruction
  shared with the OpenAI-compatible service.
- Every OpenAI-compatible preset's endpoint and model, menu selection, Custom leaving stored values alone,
  trailing-slash matching, and service names. All five preset base URLs pass `SGOpenAICompletionURL`.
- OpenAI-compatible keys belong to the base URL's lowercased host, independent of its path or port.
  Pure checks cover host derivation and legacy migration decisions. An in-memory Keychain exercises
  default/custom-host migration, preserving an existing host key, deleting the old `api-key` item,
  failures and retries, migrating before a preset changes the address, and the ` · no key` row value.
  Lyrics, AI jobs and automatic titles send nothing for a host without a key; requests for configured
  hosts carry only that host's key. The key alert saves to the host of the URL entered in the alert
  (the alert itself still needs device verification).
- AI pronunciation and cultural notes: JSON-array prompts, all three notations, sound rather than meaning,
  sparse notes, composed-character length limits, strict replies, all three service request shapes and safety
  settings, shared in-flight requests, single main-thread completion, memory/disk reuse and deletion while
  a request is running. One track-scoped notification updates peer views; cancelled jobs return no result or error.
  A real blocked-directory failure keeps AI answers in the shared memory cache until cleared.
- Saved AI round trips in a unique temporary folder: empty answers, hashed tuple isolation, malformed
  values, notation zero following the current translation language, the combined saved-file count and deletion, and retaining the newest 200 AI files.
- Switching saved translations between services and target languages on the same line objects;
  source translations stay intact and are not copied into generated-translation files. Per-song deletion
  leaves other songs, other target languages and AI notes intact, even directly after a queued save.
  Shared request tokens reject stale callbacks after replacement, per-song deletion or global deletion;
  finishing an old token cannot end a newer request. A real blocked-directory write failure
  retains results for both views in memory until removed; long local-track identifiers save under a bounded hash.
- Title language/script decisions, unchanged Latin artist names, two-line requests, local translation falling
  back when languages are unavailable, main-thread track notifications, service enablement after a missed lookup, target changes,
  out-of-order completion, a two-attempt cap with a 30-second cooldown, settings invalidation and eviction
  after 200 cached title results. The on-device translator is a harness stand-in.
  A custom NSURLProtocol intercepts Gemini HTTP requests to exercise its actual title fallback and cache:
  changed title/artist text makes a new request, while identical text reuses the answer, with no live API call.
- OpenAI-compatible replies as strict JSON arrays or single-value objects, with and without a JSON
  code fence. Wrong types, malformed fences, excessive sizes and mismatched counts fail. Base URLs
  accept HTTPS, or HTTP for localhost, 127.0.0.1, .local hosts and numeric Tailscale IPv4 addresses
  (100.64.0.0/10), and reject credentials, query strings and fragments. Tailscale checks include both
  CIDR boundaries, adjacent networks, malformed IPs, hostname lookalikes and invalid ports
  (`SGOpenAITranslationsIn`, `SGOpenAICompletionURL`). Requests follow the
  [Chat Completions format](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create).

Expected output:

```text
DeepL / Google / OpenAI: mapping, malformed replies, line counts, bounds, form encoding and URL checks passed
Bing: language, configuration, bounds, padded lines, token retry, fallback, opt-in, memo and main completion checks passed
OpenAI keys: host derivation, migration decisions, failure retry, preset isolation and lyrics/AI/title request guards passed
Claude / presets: multipart and fenced replies, errors, bounds, all five endpoints and stored selection passed
AI jobs: prompt JSON, notation, note limits, all three requests, strict replies, main completion, coalescing and memo passed
Saved AI: isolated round trip, empty values, tuple isolation, malformed data, combined count/delete and newest 200 passed
Titles: language/script detection, Latin artists, two-line request, local fallback, notification, once per track and 200-result cache passed
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

The harness compiles the network and settings code. Key reads return a fixed test value for explicitly
enabled services, with OpenAI-compatible keys held separately by account in memory. All Keychain read,
add, update and delete functions are replaced, including in the DeepL object; real entries are never
read or written. `SG_LYRICS_TEST_STORE`
redirects only the harness build's saved-file root to a unique temporary directory. Settings changed by
preset and notation tests are restored. `check-ai.m` is included by `check.m`, sharing its transport and
settings stand-ins. DeepL's transport symbol is renamed in its
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
settings alerts, real on-device translation, live AI output quality, or lyrics views taking up a result on the iPhone. Settings-page
and menu integration and localization table updates belong to the parent assignment. New visible
strings use SGL with English fallbacks; Korean text is supplied in the implementation handoff.

Title translation uses Apple's Translate first when available, then the first enabled online service in
Bing, Google, DeepL, Gemini, Claude, OpenAI-compatible order. A local failure can mean the required
languages are not installed, so it advances to that first online service; an online failure stops the job.
Only 200 title/artist results stay in memory, with up to 2000 successful identities remembered to avoid
repeat calls after result eviction. Identity includes track, original title/artist and target language.
Without a service no attempt is consumed. Failures allow one retry after 30 seconds, on a later label
refresh; changing service settings resets failed attempts and invalidates pending callbacks.
Both portrait and landscape title labels refresh when the result or translation settings change.

All changed Objective-C implementation files are compiled by this harness. The normal production paths,
including the non-test saved-file root and real Keychain declarations, were additionally checked using
`xcrun --sdk iphoneos clang -target arm64-apple-ios16.1 -fobjc-arc -fblocks -fsyntax-only` with the iOS 26.5
SDK, `-Wall -Wextra -Werror -Wno-unused-parameter` and `-Itweak/Sources`. The landscape notification harness separately compiles the complete Logos controller.
