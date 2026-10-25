# Lyrics clip harness

`SGLyricsClip.m`, the clips the lock screen shows a line of lyrics in, run on the Mac. It renders a
short line, a long one, a CJK one, two with a translation under the line, a break (the next line only, a
translation without its line left out), the last line and an empty clip, each as a Still and as Animated,
over a stand-in cover or the image given. It checks that a translation adds words under its line and none
without it, and saves that preview as `preview-translated.png`. Every file is read back with
AVFoundation and checked: its length (2 s for a still, 4 s for an animated loop), its 3:4 size, H.264,
how many frames it holds (1 or 60), words (the line, or a lone dimmed next line) between 15% and 65% of
the height and none, dimmed ones included, under the clock (the top 15%) or the media controls (the
bottom 35%), and the words the same at the end as at the start. It prints how long the default backdrop
and each clip took to make. The first frame of each clip is saved next to it as a PNG; a phone shows its
middle 9:19.5 strip.

    ./build.sh && build/lyrics-clip [cover.jpg]

The clips land in `build/clips/`.

Fallback clips use the full screen raster and the lock screen's default background: the cover blurred
(blur 60 of 100, at width 640) and darkened 45%. A photographic cover shows the blur better than the
stand-in.
Five additional still clips exercise each selected background through the real encoder and existing
decoded-frame layout checks. `OUT=<unique temporary directory>` isolates build/output artifacts.

`motion` renders Moving artwork with lyrics (`SGLyricsClipWriteOverMotion`, `motion.m`) over two stand-ins
it makes, a bright busy flag (720x1280, 30 fps, a Canvas's shape) and a dark field (904x1206, 24 fps, an
Apple Music cover's), and over any videos given: a line with the one before and after, the same with its
translation (its preview saved as `<video>-translated-preview.png`), a long line, a
stretch round the video's end, one longer than the video (written whole), a break and no words. Each is
read back and checked: length, the 3:4 cut's size, H.264, frames at up to 30 fps, words in the upper middle
and nothing white under the clock (the top 15%) or the controls (the bottom 35%), the picture moving, and the preview the same as the first
frame. With the translation, it draws the same preview again with the lines as spaces, the picture behind them
alone, and over the flag checks the picture behind the translation and the next line in the phone's strip:
little pattern left (the mean step between neighbouring pixels under 0.65 of 255; the narrower blur and fixed
band before left 1.31) and a dimmed line at more than 4.2:1 on its brightest 5% (before, 3.4:1); over other
videos it prints the same. A video whose frames decode at another size than it states (non-square pixels, made with ffmpeg's
`setsar=4/3`) must not be written and give no preview, so the line falls back to the cover; so must a video
that is gone or cut short. It also checks the artwork ID's ending (`SGLyricsClipLook`): another style or
another video gives another one. It prints each clip's time a frame against the video cut alone (`SGMotionClipShape`) and the
Animated lyrics clip, the contrast of the words with the brightest of the picture behind them, and the
memory used.

    ./build.sh && build/lyrics-clip motion [video.mp4 ...]
    build/lyrics-clip motion one video.mp4    # one line's clip alone, for its memory peak
    build/lyrics-clip motion cut video.mp4    # the video cut alone, to compare

These land in `build/motion/`. AVFoundation's encoder needs the sandbox off.
