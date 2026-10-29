#!/usr/bin/env python3
"""Breaks each rule harness/lyrics-clip guards for Messages and Vinyl, and the visible-frame margin, once in a
copy of tweak/Sources, and checks that the harness fails at that rule's check. The next-words, heading and tail-corner
mutants draw what the layouts must not."""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
CLIP = "Shared/LockScreenLyrics/SGLyricsClip.m"

# name, before, after, the check that must fail, the run (scenes: `lyrics-clip scenes`; unchanged: unchanged.sh)
MINE_FILL = "        setFill(context, i == 1 ? kMine : kTheirs, 1);\n        CGContextAddPath(context, path);\n        CGContextFillPath(context);\n"
STACK_TOP = "    CGFloat y = H * kLowest - tall;   // from the top\n"
CASES = [
    ("band-bottom", "kSafeScreenBottom = 0.65,", "kSafeScreenBottom = 0.7,",
     "FAIL nothing drawn below 65% of the screen", "scenes"),
    ("band-top", "kSafeScreenTop = 0.17,", "kSafeScreenTop = 0.1,",
     "FAIL nothing drawn above 17% of the screen", "scenes"),
    ("blue", "kMine = 0x0A84FF,", "kMine = 0x2F5BFF,", "FAIL the line in a #0A84FF bubble", "scenes"),
    ("next-words", "        } else {\n            CGFloat dot = fontSize * kDot",
     "        } else if (YES) {\n            CTFontRef f = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, fontSize, NULL);\n"
     "            drawIn(context, styled(next, f, 1, lineHeight, 0, kCTTextAlignmentNatural), inner, 0);\n"
     "            CFRelease(f);\n        } else {\n            CGFloat dot = fontSize * kDot",
     "FAIL the next line's words never show", "scenes"),
    ("typing-always", "BOOL shown[3] = {previous.length > 0, line.length > 0, next.length > 0};",
     "BOOL shown[3] = {previous.length > 0, line.length > 0, YES};",
     "FAIL no typing bubble without a next line", "scenes"),
    ("sides", "BOOL onLeft = (i != 1) != flipped;", "BOOL onLeft = (i == 1) != flipped;",
     "FAIL the line sung last on the left", "scenes"),
    ("no-mirror", "BOOL flipped = rightToLeft(", "BOOL flipped = NO && rightToLeft(",
     "FAIL mirrored right to left", "scenes"),
    ("stack-bottom", STACK_TOP, "    CGFloat y = H * kLowest - tall - 20;   // from the top\n",
     "FAIL the bubbles end at 65% of the screen", "scenes"),
    ("heading", STACK_TOP, STACK_TOP + "    setFill(context, kSecondary, 1);\n"
     "    CGContextFillRect(context, CGRectMake(left, round(H - y + 20), 200, 16));\n",
     "FAIL nothing but the three bubbles drawn", "scenes"),
    ("tail-corner", MINE_FILL, MINE_FILL + "        CGContextFillRect(context, CGRectMake(onLeft ? box.origin.x : CGRectGetMaxX(box) - 20,"
     " box.origin.y, 20, 20));\n", "FAIL every bubble's four corners round alike", "scenes"),
    ("no-pill", "i == 2 ? box.size.height / 2 : W * kBubbleRadius", "W * kBubbleRadius", "FAIL the typing bubble a pill", "scenes"),
    ("mine-lines", "kMineLines = 4,", "kMineLines = 5,", "FAIL a long line set at 0.6 of the size holds 4 lines", "scenes"),
    ("theirs-lines", "kTheirsLines = 2;", "kTheirsLines = 3;", "FAIL a long line sung last holds 2 lines", "scenes"),
    ("bubble-width", "kBubbleWidth = 0.74,", "kBubbleWidth = 0.9,",
     "FAIL a bubble is at most 74% of the stack wide", "scenes"),
    ("record-most", "kRecordMost = 0.6,", "kRecordMost = 0.5,", "FAIL the record 60% of the card across", "scenes"),
    ("record-least", "kRecordLeast = 0.45,", "kRecordLeast = 0.4,", "FAIL the record 45% across under a long line", "scenes"),
    ("not-centred", "top = round(H * kTop + glow + (room - block) / 2);", "top = round(H * kTop + glow);",
     "FAIL the record and the words centred in the band together", "scenes"),
    ("no-label", "    if (cover) {\n        CGFloat w = CGImageGetWidth(cover)", "    if (NO) {\n        CGFloat w = CGImageGetWidth(cover)",
     "FAIL the cover is the label", "scenes"),
    ("label-size", "kLabel = 0.38,", "kLabel = 0.45,", "FAIL the cover is the label", "scenes"),
    ("no-glow", "kGlowAlpha = 0.12;", "kGlowAlpha = 0;", "FAIL a glow about the record", "scenes"),
    ("rim", "kRimAlpha = 0.25,", "kRimAlpha = 0.12,", "FAIL the rim 25% white", "scenes"),
    ("words-gap", "kRecordGap = 0.04,", "kRecordGap = 0.08,", "FAIL the words centred 4% under the record", "scenes"),
    ("next-dim", "kVinylNextAlpha = 0.55,", "kVinylNextAlpha = 0.45,", "FAIL the next line beneath, 55% white", "scenes"),
    ("line-height", "kVinylLineHeight = 1.2,", "kVinylLineHeight = 1.05,", "FAIL the line's lines 1.20 of its size apart (", "scenes"),
    ("cjk-line-height", "kVinylCJKLineHeight = 1.35;", "kVinylCJKLineHeight = 1.2;",
     "FAIL the line's lines 1.35 of its size apart with CJK", "scenes"),
    ("scene-animated", "style == SGLyricsClipAnimated && !SGLyricsClipIsScene(layout) ?", "style == SGLyricsClipAnimated ?",
     "FAIL the clip reads back", "scenes"),
    ("left-margin", "kMargin = 0.08,", "kMargin = 0.24,", "FAIL existing layout keeps the 8%", "unchanged"),
]

for name, before, after, expected, run in CASES:
    with tempfile.TemporaryDirectory(prefix=f"vitrine-lyrics-clip-{name}.", dir="/tmp") as tmp:
        src = Path(tmp) / "Sources"
        shutil.copytree(ROOT / "tweak/Sources", src)
        target = src / CLIP
        source = target.read_text()
        if source.count(before) != 1:
            raise SystemExit(f"{name}: mutation anchor is not unique")
        target.write_text(source.replace(before, after))
        out = Path(tmp) / "build"
        env = dict(os.environ, SRC=str(src), OUT=str(out))
        if run == "scenes":
            subprocess.run(["sh", str(HERE / "build.sh")], env=env, check=True)
            result = subprocess.run([str(out / "lyrics-clip"), "scenes"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        else:
            result = subprocess.run(["sh", str(HERE / "unchanged.sh")], env=env, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True)
        if result.returncode == 0 or expected not in result.stdout:
            print(result.stdout)
            raise SystemExit(f"{name}: did not fail at its regression boundary")
        print(f"mutation caught: {name}: {expected}")
