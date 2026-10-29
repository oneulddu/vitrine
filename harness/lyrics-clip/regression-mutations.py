#!/usr/bin/env python3
"""Break layout bounds, sharp-cover selection and the local gradient in disposable source copies."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
cases = [
    ("margin", "kMargin = 0.08,", "kMargin = 0.24,", "FAIL existing layout keeps the 8%"),
    ("vertical-mapping", "#define kCentreY ((kTextScreenCentre - kFrameScreenTop) / kFrameScreenHeight)",
     "#define kCentreY 0.4", "FAIL existing layout is centred 40%"),
    ("crop-assumption", "CGFloat screen = size.width, width", "CGFloat screen = size.width * (9 / 19.5 * 4 / 3), width",
     "FAIL existing layout keeps the 8%"),
    ("column", "kColumn = 0.84;", "kColumn = 0.52;", "FAIL laid-out sentence spans over 70%"),
    ("vinyl-column", "width = round(W * kColumn);", "width = round(W * .52);",
     "FAIL laid-out sentence spans over 70% of visible width (layout 4:"),
    ("contrast", "kArtworkScrimAlpha = 0.94,", "kArtworkScrimAlpha = 0.2,", "FAIL current 4.5:1 and dimmed 3:1"),
    ("plateau", "CGFloat fade = exp(-(dx * dx + dy * dy));", "CGFloat fade = 1;",
     "FAIL side gradient continuously fades"),
    ("blur", "(SGLyricsBackgroundStyle){SGLyricsBackgroundCover, 0, 0, 0}",
     "(SGLyricsBackgroundStyle){SGLyricsBackgroundBlur, 0, 60, 0}", "FAIL cover is sharp aspect fill"),
]
for name, before, after, expected in cases:
    with tempfile.TemporaryDirectory(prefix=f"lyrics-{name}-") as temp:
        src = Path(temp) / "Sources"
        shutil.copytree(ROOT / "tweak/Sources", src)
        path = src / "Shared/LockScreenLyrics/SGLyricsClip.m"
        text = path.read_text()
        if text.count(before) != 1:
            raise SystemExit(f"{name}: anchor is not unique")
        path.write_text(text.replace(before, after))
        result = subprocess.run(["sh", str(ROOT / "harness/lyrics-clip/regression.sh")],
            env=dict(os.environ, SRC=str(src)), capture_output=True, text=True)
        if result.returncode == 0 or expected not in result.stdout:
            print(result.stdout, result.stderr)
            raise SystemExit(f"{name}: mutation was not caught")
        print(f"mutation caught: {name}: {expected}")
