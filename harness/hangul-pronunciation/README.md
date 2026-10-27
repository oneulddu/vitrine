# Hangul pronunciation harness

Offline checks of the real `tweak/Sources/Shared/Lyrics/Romanise.m` transforms and
`tweak/Sources/Shared/Lyrics/LyricsSettings.m` callbacks. Run from the repository root
on an Apple Silicon Mac with Xcode:

    bash harness/hangul-pronunciation/check.sh
    bash harness/hangul-pronunciation/settings.sh

The Foundation check covers kana, combined small kana, final consonants, long vowels,
katakana, tokenizer readings of kanji, Mandarin pinyin, unmapped syllables, the
4,000-UTF-16-unit limit, and Latin/hiragana compatibility across alphabet changes.
`ROMANISE_SOURCE` can select a temporary source copy for mutation checks.

The Catalyst check uses lightweight row/page and preference-store doubles to exercise
the real settings factories: alphabet choices, immediate notifications and readings,
the existing pronunciation switch, and the saved Japanese-reading choice.
It does not verify screen rendering or device integration.

Both scripts build and run uniquely named executables (`hangul-pronunciation-check`
and `hangul-pronunciation-settings`) in fresh temporary directories, removed on exit.
Defaults are process-local; no saved preferences, simulator, phone, or network are used.
Failures print a diagnostic and exit nonzero rather than crashing.
