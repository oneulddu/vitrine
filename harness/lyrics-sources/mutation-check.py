#!/usr/bin/env python3
"""Break each source contract in an isolated generated source tree, never in the checkout."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent.parent / "tweak/Sources"
MUTATIONS = [
    ("QRC absolute clocks", "QQMusic.m",
     "piece.start = (NSInteger)at;", "piece.start = (NSInteger)(at + start);",
     "line.words[0].start == 1234", False),
    ("QRC expansion bound", "QQMusic.m",
     "static const NSUInteger kQRCMaxBytes = 1 << 20;",
     "static const NSUInteger kQRCMaxBytes = 1 << 21;",
     "atLimit stringByAppendingString", False),
    ("mixed malformed QRC clocks", "QQMusic.m",
     r'@"\\(([^(),]*),([^()]*)\\)"', r'@"\\((\\d+),(\\d+)\\)"',
     "mixed.synced && !mixed.wordTimed", False),
    ("short artist interior", "SongMatch.m",
     "if (shorter.length >= 4) return [longer containsString:shorter];",
     "return [longer containsString:shorter];",
     '!SGLyricsSameArtist(@"MIURA"', False),
    ("joined credit aliases", "SongMatch.m",
     '''        NSArray *parts = [component componentsSeparatedByCharactersInSet:
            [NSCharacterSet characterSetWithCharactersInString:@"()（）、"]];''',
     '''        NSArray *parts = [namesJoinedIn(credit) arrayByAddingObjectsFromArray:
            [credit componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"()（）、"]]];''',
     'SGLyricsSameArtist(@"Other & IU (아이유) & Guest", @"IU")', False),
    ("worker parsing", "LyricsSources.m",
     "        done(data, reply);",
     "        dispatch_async(dispatch_get_main_queue(), ^{ done(data, reply); });",
     "!NSThread.isMainThread", True),
    ("NetEase title", "NetEase.m",
     "            if (![SGLyricsMatchKey(song[@\"name\"]) isEqualToString:SGLyricsMatchKey(title)]) continue;",
     "", 'id=4', True),
]

with tempfile.TemporaryDirectory(prefix="vitrine-lyrics-mutations-") as directory:
    copied = Path(directory) / "Sources"
    shutil.copytree(SOURCE, copied)
    for name, file, before, after, evidence, transport_only in MUTATIONS:
        path = copied / "Shared/LyricsSources" / file
        original = path.read_text()
        if original.count(before) != 1:
            raise SystemExit(f"{name}: mutation anchor is not unique in the live source")
        path.write_text(original.replace(before, after))
        try:
            command = ["sh", str(HERE / "build.sh")]
            if transport_only:
                command.append("--transport-only")
            result = subprocess.run(command, env={**os.environ, "LYRICS_SOURCE_ROOT": str(copied)},
                                    capture_output=True, text=True, timeout=120)
            output = result.stdout + result.stderr
            if result.returncode == 0 or "FAILED line" not in output or evidence not in output:
                print(output)
                raise SystemExit(f"{name}: did not fail at its behavior assertion")
            failure = next(line for line in output.splitlines() if "FAILED line" in line)
            print(f"{name}: rejected ({failure})", flush=True)
        finally:
            path.write_text(original)
print(f"All {len(MUTATIONS)} mutations failed as expected; checkout unchanged.")
