#!/usr/bin/env python3
"""Run focused regressions against isolated, deliberately broken production copies."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CASES = [
    ("artist-delete", "Shared/LockScreenLyrics/LockScreenLyrics.x",
     "@[SGLyricsTranslationSavedNotification, SGLyricsTranslationsDidChangeNotification]",
     "@[SGLyricsTranslationSavedNotification]",
     "FAIL paused artist row removes deleted translation without a view"),
    ("artwork-delete", "Shared/LockScreenLyrics/LyricsArtwork.x",
     "@[SGLyricsTranslationSavedNotification, SGLyricsTranslationsDidChangeNotification]",
     "@[SGLyricsTranslationSavedNotification]",
     "FAIL paused artwork removes deleted translation without a lyrics view"),
    ("prefetch-priority", "Shared/LockScreenLyrics/LyricsArtwork.x",
     "if (prefetch) sg_prefetch = job;\n        else [sg_clipRequests addObject:job];",
     "[sg_clipRequests addObject:job];",
     "FAIL same-track seeks drop superseded prefetches before encoding and current demand goes first"),
    ("activity-restore", "Shared/LiveActivity/LiveActivity.x",
     "SGLyricsLoadTranslation(trackID, language, lines, ^BOOL {",
     "if (NO) SGLyricsLoadTranslation(trackID, language, lines, ^BOOL {",
     "FAIL Live Activity restores saved generated translation without opening lyrics"),
    ("cleanup-order", "Shared/LockScreenLyrics/LyricsArtwork.x",
     "enqueueClip(^{\n"
     "                [NSFileManager.defaultManager removeItemAtURL:folder() error:nil];\n"
     "                [NSFileManager.defaultManager createDirectoryAtURL:folder() withIntermediateDirectories:YES attributes:nil error:nil];\n"
     "            }, NO);",
     "dispatch_async(sg_queue, ^{\n"
     "                [NSFileManager.defaultManager removeItemAtURL:folder() error:nil];\n"
     "                [NSFileManager.defaultManager createDirectoryAtURL:folder() withIntermediateDirectories:YES attributes:nil error:nil];\n"
     "            });",
     "FAIL new-track clip URL remains readable after queued cache cleanup"),
]

for name, relative, before, after, expected in CASES:
    with tempfile.TemporaryDirectory(prefix=f"vitrine-{name}.", dir="/tmp") as tmp:
        src = Path(tmp) / "Sources"
        shutil.copytree(ROOT / "tweak/Sources", src)
        target = src / relative
        source = target.read_text()
        if source.count(before) != 1:
            raise SystemExit(f"{name}: mutation anchor is not unique")
        target.write_text(source.replace(before, after))
        env = dict(os.environ, SRC=str(src), OUT=str(Path(tmp) / "build"))
        # The normal script runs off then on; artist-row mutation needs the on process
        # even if a different mutant has already failed the off process.
        result = subprocess.run(["sh", str(ROOT / "harness/now-playing/build.sh")],
                                env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if result.returncode == 0 or expected not in result.stdout:
            print(result.stdout)
            raise SystemExit(f"{name}: did not fail at its regression boundary")
        print(f"mutation caught: {name}: {expected}")
