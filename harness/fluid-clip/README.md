# Fluid clip harness

`SGFluidClip.m`, the clip the lock screen shows for a song with no Canvas and no animated cover when
Full-screen artwork is Every song, run on the Mac. It renders the loop over a stand-in cover or the image
given through the shared selected-background renderer, then reads it back with AVFoundation:
4 s, 3:4 at the full fallback raster, H.264, 60 frames, a gentle breath with no loop seam, 45% default
darkening, and the preview matching the first frame. The old moving-blur compositor and duplicate
encoder have been removed; `SGFluidClip` is the lyric-free adapter to `SGLyricsClip`.
It prints how long the clip took to write.

    ./build.sh && build/fluid-clip [cover.jpg]

The clip lands in `build/clips/`, with its first and middle frames as PNGs.
`OUT=<unique temporary directory>` keeps previous artifacts untouched.
