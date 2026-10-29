# Lyrics clip harness

`SGLyricsClip.m`, the clips the lock screen shows a line of lyrics in, run on the Mac. It renders a
short line, a long one, a CJK one, two with a translation under the line, a break (the next line only, a
translation without its line left out), the last line, an empty clip, and two blocks too tall for the
space (a very long Latin line and a very long CJK one, each with a long translation, which drop lines and
end in an ellipsis), each as a Still and as Animated in the Left layout and as a Still in Centered
(`-centered`) and Poster (`-poster`), over a stand-in cover or the image given. It checks each layout's
place on the preview frame: Left 8% of the strip in, Centered in its middle at Left's height, Poster's line
larger and heavier, left-aligned, with no next line and its translation kept (`preview-poster-translated.png`). It checks that a translation adds words under its line and none
without it, and saves that preview as `preview-translated.png`. Every file is read back with
AVFoundation and checked: its length (2 s for a still, 4 s for an animated loop), its 3:4 size, H.264,
how many frames it holds (1 or 60), words (the line, or a lone dimmed next line) between 15% and 65% of
the height and none, dimmed ones included, under the clock (the top 15%) or the media controls (the
bottom 35%), and the words the same at the end as at the start (within 6% for a block filling the space,
for the encoder's loss on the letters' edges). It prints how long the default backdrop
and each clip took to make. The first frame of each clip is saved next to it as a PNG; a phone shows its
middle 9:19.5 strip.

    ./build.sh && build/lyrics-clip [cover.jpg]

The clips land in `build/clips/`.

Fallback clips use the full screen raster and the lock screen's default background: the cover blurred
(blur 60 of 100, at width 640) and darkened 45%. A photographic cover shows the blur better than the
stand-in.
Five additional still clips exercise each selected background through the real encoder and existing
decoded-frame layout checks. `OUT=<unique temporary directory>` isolates build/output artifacts.

`scenes.m` checks the two layouts that paint the whole picture, Messages and Vinyl, against the spec's numbers as the
review revised them (notes/cleanroom-specs/chroma-plus/lockscreen-layouts.md; W is the card's width, the 9:19.5 strip
the phone shows, H the height). Fixtures in both: the line with the one before and the next, no line before, no next
line, a very long Latin and a very long CJK line, right to left (Arabic), emoji, and for Vinyl no cover; each preview
is saved as `build/scenes/<layout>-<fixture>.png`. Every one draws only between 17% and 65% of H, where the other
layouts keep their words. Messages: the line in a #0A84FF bubble, another next line draws the very same frame (its
words never show), no grey bubble without a next line and the dots under the line with one, the line sung last at the
stack's left edge and the line at its right (swapped right to left), the stack ending at 65% of H with nothing but its
bubbles drawn, every bubble's four corners alike and the typing one a pill, a long line held to 4 lines and a long
line sung last to 2 at 0.6 of the size, a bubble at most 74% of the stack wide, and the cover and translation left
out. Vinyl: the record 0.6 W across when the words fit and 0.45 W under a long line, centred, the record and the words
centred in the band together, a glow about it and a 25% white rim, the cover as a label 38% of the record (a flat dark
one without), the words centred 4% W under it, the line's lines 1.2 of its size apart (1.35 with CJK), the next line
at 55% white, and the line sung last and the translation left out. Each layout's clip is written Still and Animated
and read back: one frame, held 2 s or 4 s.

    ./build.sh && build/lyrics-clip scenes [cover.jpg]

`unchanged.sh` builds `frames.m` twice, against SGLyricsClip.m as it was at BASE (the commit before Messages and
Vinyl) and against the tree's, and fails on any pixel of any case above in Left, Centered or Poster that differs,
with the scenes' inputs handed to today's. `mutations.py` breaks each of those rules once in a copy of the sources and
checks the harness fails at that rule.

    sh unchanged.sh
    python3 mutations.py

`motion` renders Moving artwork with lyrics (`SGLyricsClipWriteOverMotion`, `motion.m`) over two stand-ins
it makes, a bright busy flag (720x1280, 30 fps, a Canvas's shape) and a dark field (904x1206, 24 fps, an
Apple Music cover's), and over any videos given: a line with the one before and after, the same with its
translation (its preview saved as `<video>-translated-preview.png`), a long line, a
stretch round the video's end, one longer than the video (written whole), a break, no words, and the two
blocks too tall for the space with the lines either side; over the two stand-ins in all three layouts, over
videos given in Left. Each is
read back and checked: length, the 3:4 cut's size, H.264, frames at up to 30 fps, words in the upper middle
and nothing white under the clock (the top 15%) or the controls (the bottom 35%), the picture moving, and the preview the same as the first
frame. With the translation, it draws the same preview again with the lines as spaces, the picture behind them
alone, and over the flag checks the picture behind the translation and the next line in the phone's strip:
little pattern left (the mean step between neighbouring pixels under 0.65 of 255; the narrower blur and fixed
band before left 1.31) and a dimmed line at more than 4.2:1 on its brightest 5% (before, 3.4:1); over other
videos it prints the same. A video whose frames decode at another size than it states (non-square pixels, made with ffmpeg's
`setsar=4/3`) must not be written and give no preview, so the line falls back to the cover; so must a video
that is gone or cut short. It also checks the artwork ID's ending (`SGLyricsClipLook`): another style,
layout or video gives another one. Last it makes a video dark at its start and bright later (2 s of mid
grey, then the flag, 720x960) and writes the lines as spaces over its first 3.5 s: the band must keep under
0.8 of what judging by the first frame alone kept (0.4, which a preview over the grey alone still gives),
from the first frame on, and the preview for the same stretch must keep the same. It prints each clip's time a frame against the video cut alone (`SGMotionClipShape`) and the
Animated lyrics clip, the contrast of the words with the brightest of the picture behind them, and the
memory used.

    ./build.sh && build/lyrics-clip motion [video.mp4 ...]
    build/lyrics-clip motion one video.mp4    # one line's clip alone, for its memory peak
    build/lyrics-clip motion cut video.mp4    # the video cut alone, to compare

These land in `build/motion/`. AVFoundation's encoder needs the sandbox off.
