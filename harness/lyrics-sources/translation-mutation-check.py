#!/usr/bin/env python3
"""Remove live translation guarantees in isolated source copies; require behavioral failures."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent.parent / "tweak/Sources"
publication = "if (translated) keep(track, translated, NO);"
without_save = """if (translated) {
            sg_lyrics[track] = translated;
            [NSNotificationCenter.defaultCenter postNotificationName:SGKaraokeLinesKeptNotification object:track];
        }"""
mutations = [
    ("community-stale", "superseded community target",
     " || ![language isEqualToString:SGLyricsTranslationLanguage()]", "",
     "!SGKaraokeLinesForTrack(track).firstObject.translation"),
    ("ttml-stale", "superseded worker result",
     "    lines = SGLyricsProviderTranslationsForLanguage(lines, SGLyricsTranslationLanguage());",
     "", "!SGKaraokeLinesForTrack(track).firstObject.translation"),
    ("received", "already received English",
     "for (NSString *track in sg_lyrics.allKeys) keep(track, sg_lyrics[track], NO);",
     "for (NSString *track in sg_lyrics.allKeys) translate(track);",
     "!SGKaraokeLinesForTrack(track).firstObject.translation"),
    ("delayed", "delayed offline save", publication, without_save,
     '[restored.translation isEqual:@"Hello"]'),
    ("cached", "cached offline save", publication, without_save,
     '[restored.translation isEqual:@"Hello"]'),
    ("delayed", "delayed notification",
     "    if (lines.count) translate(track);\n    announce(track);",
     "    if (lines.count) translate(track);", "translatedNotification"),
    ("cached", "cached notification",
     "    if (lines.count) translate(track);\n    announce(track);",
     "    if (lines.count) translate(track);", "translatedNotification"),
]

with tempfile.TemporaryDirectory(prefix="vitrine-translation-mutations.", dir="/tmp") as directory:
    copied = Path(directory) / "Sources"
    shutil.copytree(SOURCE, copied)
    path = copied / "Shared/Lyrics/KaraokeSource.x"
    original = path.read_text()
    for scenario, name, before, after, evidence in mutations:
        if original.count(before) != 1:
            raise SystemExit(f"{name}: mutation anchor is not unique")
        mutated = original.replace(before, after)
        if scenario == "community-stale":
            # Both reply validation and keeper provenance filtering independently prevent
            # stale English from appearing. Reproduce the old path by removing both barriers.
            barrier = "    lines = SGLyricsProviderTranslationsForLanguage(lines, SGLyricsTranslationLanguage());"
            if mutated.count(barrier) != 1:
                raise SystemExit(f"{name}: keeper barrier is not unique")
            mutated = mutated.replace(barrier, "")
        path.write_text(mutated)
        result = subprocess.run(
            ["sh", str(HERE / "state-build.sh")],
            env={**os.environ, "LYRICS_SOURCE_ROOT": str(copied), "VITRINE_TRANSLATION_CASE": scenario},
            capture_output=True, text=True, timeout=120,
        )
        output = result.stdout + result.stderr
        if result.returncode == 0 or "FAILED line" not in output or evidence not in output:
            print(output)
            raise SystemExit(f"{name}: did not fail at the required behavior")
        failure = next(line for line in output.splitlines() if "FAILED line" in line)
        print(f"{name}: rejected ({failure})", flush=True)
print("All seven mutations failed as expected; checkout unchanged.")
