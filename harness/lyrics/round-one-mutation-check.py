#!/usr/bin/env python3
"""Prove the round-one checks reject each regression, without editing the working tree."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
VIEW = "Redesigned/Lyrics/SGRKaraokeView.m"
AUTO = "Redesigned/Lyrics/AutoTranslation.m"
MUTATIONS = [
    ("R2-LY-1-view", VIEW,
     "&& translationsDiffer(_lines, kept)) {",
     "&& !_hasTranslation && SGLyricsHasTranslations(kept)) {",
     "FAIL provider removal clears English from loaded timed karaoke without moving scroll"),
    ("R2-LY-1-unchanged", VIEW,
     "&& translationsDiffer(_lines, kept)) {",
     "&& YES) {",
     "FAIL unchanged provider translations preserve presented rows without another restyle"),
    ("LV-01", VIEW,
     "MAX(MAX(0, lastTop - _focusTop), bottom - visibleBottom)",
     "MAX(0, lastTop - _focusTop)",
     "FAIL the entire final line and credit can scroll above"),
    ("LV-02", AUTO,
     "if (contextual || [self.missing containsIndex:i]) {",
     "if (YES) {",
     "FAIL provider 5 receives only unresolved lines"),
    ("LV-03-LYRICSRC-04", AUTO,
     "dispatch_async(worker, ^{",
     "dispatch_block_t analysis = ^{",
     "FAIL view load and styling never run language recognition on main"),
]

for name, relative, before, after, expected in MUTATIONS:
    with tempfile.TemporaryDirectory(prefix="vitrine-lyrics-mutation-", dir="/tmp") as temporary:
        sources = Path(temporary) / "Sources"
        shutil.copytree(ROOT / "tweak/Sources", sources)
        path = sources / relative
        text = path.read_text()
        if text.count(before) != 1:
            raise SystemExit(f"{name}: mutation anchor is not unique")
        text = text.replace(before, after, 1)
        if name == "LV-03-LYRICSRC-04":
            before_end = (
                "dispatch_async(dispatch_get_main_queue(), ^{ done([answer[0] boolValue], "
                "[answer[1] length] ? answer[1] : nil); });\n    });"
            )
            if text.count(before_end) != 1:
                raise SystemExit(f"{name}: mutation end is not unique")
            text = text.replace(before_end, before_end[:-3] + "}; analysis();", 1)
        path.write_text(text)
        environment = dict(os.environ, HARNESS_SOURCE_DIR=str(sources),
                           HARNESS_BUILD_DIR=str(Path(temporary) / "build"),
                           SG_LYRICS_ROUND_ONE_ONLY="1")
        result = subprocess.run([str(ROOT / "harness/lyrics/translation-check.sh")],
                                env=environment, capture_output=True, text=True, timeout=120)
        failures = [line for line in result.stdout.splitlines() if line.startswith("FAIL ")]
        if result.returncode == 0 or expected not in result.stdout:
            print(result.stdout, result.stderr)
            raise SystemExit(f"{name}: expected behavioral regression was not detected (exit {result.returncode})")
        print(f"PASS mutation {name}: regression exits {result.returncode}")
        for failure in failures:
            print(failure)
