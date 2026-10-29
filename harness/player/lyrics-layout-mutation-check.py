#!/usr/bin/env python3
"""Restore the moving artwork viewport in a temporary source copy; the check must reject it."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
relative = Path("Redesigned/Player/PlayerLyrics.x")
source = (root / "tweak/Sources" / relative).read_text()
fixed = "CGRectMake(CGRectGetMinX(host.bounds), lines, host.bounds.size.width,"
broken = "CGRectMake(CGRectGetMinX(area), lines, area.size.width,"
if source.count(fixed) != 1:
    raise SystemExit("mutation anchor is not unique")
with tempfile.TemporaryDirectory(prefix="lyrics-layout-mutation-") as temporary:
    target = Path(temporary) / relative
    target.parent.mkdir(parents=True)
    target.write_text(source.replace(fixed, broken, 1))
    result = subprocess.run(
        ["sh", str(root / "harness/player/lyrics-layout-check.sh")],
        env=dict(os.environ, SRC=temporary), capture_output=True, text=True, timeout=60,
    )
    if result.returncode != 1 or "FAIL artwork x=32: lyric viewport" not in result.stderr:
        print(result.stdout, result.stderr)
        raise SystemExit("moving-artwork mutation was not rejected by the viewport check")
    print("PASS mutation: artwork x=32 moves the lyric viewport and exits 1")
