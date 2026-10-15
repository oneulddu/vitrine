# Lyrics translation check

Run `harness/lyrics-translation/build.sh` from the repository, or `./build.sh` here. It compiles the
checkout's production sources into a Mac Catalyst binary, then runs offline with no simulator. The
replies are made up; no real lyrics or API keys are stored and no translation service is contacted.

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
- OpenAI-compatible replies as strict JSON arrays or single-value objects, with and without a JSON
  code fence. Wrong types, malformed fences, excessive sizes and mismatched counts fail. Base URLs
  accept HTTPS, or HTTP only for localhost, 127.0.0.1 and .local hosts, and reject credentials, query
  strings and fragments (`SGOpenAITranslationsIn`, `SGOpenAICompletionURL`). Requests follow the
  [Chat Completions format](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create).

Expected output:

```text
DeepL / Google / OpenAI: mapping, malformed replies, line counts, bounds, form encoding and URL checks passed
lyrics translation: all checks passed
```

The new translators share the bounded transport in `DeepL.m`, so that file is linked alongside
`GoogleTranslate.m` and `OpenAITranslate.m`. It receives at most 512 KiB per reply, uses ephemeral
sessions without disk caching, refuses redirects, and retries 429 up to three times with jittered
1/2/4-second backoff. Google and OpenAI-compatible services retry 5xx too. Google checks its opt-in
before each attempt and batch. Each service keeps up to 32 successful song/language results in memory,
checks that the source text still matches, and completes on main. DeepL sends at most 50 texts and
16000 UTF-16 units per batch; Google rejects individual lines over 3500 units instead of truncating
or splitting their characters. Whole inputs are limited to 2000 lines and 128000 UTF-16 units.

The harness compiles the network and settings code but does not exercise live requests, backoff,
Keychain storage, alerts, or the runtime line-by-line fallback. It does not test saved translations or
lyrics views taking up a result. Settings-page/menu integration and localization table updates are
outside this assignment. New visible strings use SGL with English fallbacks; Korean text is supplied
in the implementation handoff.
