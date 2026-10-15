# Lyrics sources check

`./build.sh` checks, on the Mac as a Mac Catalyst binary, with no simulator and no network:

- the word splitting in `Shared/Lyrics/KaraokeTiming.m`: long Thai, Lao, Khmer and Burmese lines with no
  spaces come apart at the dictionary's words, the pieces make up the line exactly, and Latin, Chinese and
  Japanese lines split as before. The pieces are printed, so a script the system does not split shows;
- KuGou's KRC (`KuGou.m`, read by `SGLyricsPieceLines` in `NetEase.m`): packed here the way KuGou packs
  it, then unpacked and read, with the word times, the joining and the line ends checked;
- the QQ Music and KuGou asks against made-up search replies: titles, singers and lengths that do not
  fit are passed over, the closest KuGou lengths are tried first and at most three, and QQ's LRC is read;
- Bugs' second-to-millisecond rounding, malformed and backwards sheets, plain fallback, and title,
  artist and four-second duration matching (a music video's length does not stand in for the track's);
- Genie's bounded HTML rows and entity decoding, browser headers, JSONP removal, numeric-key
  validation and millisecond sorting;
- LyricsPlus' Line, Word and Syllable shapes, joining, backing vocals, catalog credit and fallback host;
- Deezer's word/line/plain preference, title/artist/duration matching, missing or unsafe ARL, in-memory
  JWT reuse, and one refresh on either a GraphQL or HTTP authentication failure. Cookies, tokens and
  lyrics in these checks are invented; no Keychain item is read or written;
- odd JSON types, oversized text, non-finite clocks, and completion on main from a worker queue;
- LRCLIB manual search: synced-first and nearest-duration ranking, shaped records, the 20-record
  limit, first 100 input records, 256 KiB UTF-8 / 4000-line sheet caps (including CRLF), empty replies,
  the User-Agent and lookup of a pinned id through the bounded source transport;
- Japanese reading: `君の名前を呼ぶ` becomes `きみのなまえをよぶ`, a kana-only line returns nil,
  Latin and particles stay as written, and changing between romaji and hiragana changes the cache key.

`./build.sh krc.json qq.json` also reads real replies saved from `lyrics.kugou.com/download` and QQ's
`GetPlayLyricInfo`, and prints how many lines each has. None are kept here, since they are real lyrics.

A successful run ends with:

```text
Bugs, Genie, LyricsPlus, Deezer: parser, matching, fallback, auth and main-queue checks passed
lyrics-sources: all checks passed
```

The transport is replaced by an offline responder. This checks request URLs, headers and bodies, but
not the live services, transport size cancellation, real Deezer authentication, Keychain access or the
settings alert on a phone. The source order and on-device lyrics rendering are outside this harness. The shared
transport and settings integration can be checked with clang's syntax-only mode without a Theos build.
No replies containing real lyrics are stored in the fixtures.

`sh ./state-build.sh` checks the actual keeper and source walk as a second Mac Catalyst binary. Only
Spotify's Logos hooks are omitted; the route getter and the pinned/provider replies are replaced by
made-up answers. It checks offset clamps and deletion, 500-track and 500-pin limits, negative total
delay and seeks, a cached clock read from worker threads, a route notification sent off main,
immediate pin visibility and credit, rejected empty choices, late replies after pin/unpin, a stored
pin fetched before the normal walk, failed-pin fallback, and instrumentals. It also compiles the actual
`LyricsHook.x` code before the Logos declarations: pinned plain/instrumental choices beat later timed
Spotify lines, request generations survive donor rewriting, and stale donor, held and Spotify
deliveries are discarded after pin/unpin (including a change while awaiting the source callback).
Its defaults use a fresh
suite removed on exit. This does not test Bluetooth hardware, the hook installation or Spotify's UI.
