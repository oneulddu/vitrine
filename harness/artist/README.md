# Artist harness

Spotify's artist page mocked under its own class names and accessibility identifiers (from
`trees/clean/artist/01.txt` and `05.txt`, recorded 2026-09-16), so `Redesigned/Artist/` can be laid out and
looked at on the Mac without the phone.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install booted build/ArtistHarness.app
    xcrun simctl launch booted com.vojta.artistharness            # at rest
    xcrun simctl launch booted com.vojta.artistharness collapsed  # the header scrolled into its 100pt bar

The Music list is a real self-sizing collection view holding the sections in the order the tree has them,
the two video sections included, so `ArtistSections.x` drops them the way it does on the phone: the shelf
first, then its heading and spacer once the list lays out again. At 2 s the log lists every cell's height.

`logo` on the launch line, with `-spotifyglass.redesign.artist.logo NO` after it so Apple Music's own logo does
not arrive as well, hands the header a logo at 2.5 s and takes it away at 4.5 s, with the page on screen. The log
says, before, as each arrives or leaves and a second later, where the logo and the name are and whether they are
fading and moving: the two cross over, the logo grows out of the name's place, and gone, the logo is hidden.

`veil` / `veil-off` check the scroll veil as on the album (`../album/README.md`, `../album/hero-veil-check.h`).
`verify-play` checks the row's Play: unset, the white capsule 48pt tall in the page's color with 48pt buttons 16pt
off it; with `-spotifyglass.redesign.artist.roundPlay YES` a 64pt white circle centered on the page with its glyph
alone and "Play" as its VoiceOver name, 44pt buttons 20pt off and level with it; with
`-spotifyglass.redesign.playInPageColour NO` the glyph in the accent (Spotify's green here) instead. It logs a PASS
line and a SHOT for a screenshot, or a FAIL and exits 1.

What it does not cover: the repaint hook (so the mock's cells are left unpainted), the real z-order of the
pinned header bar against the list, and the element framework's own sizing.
