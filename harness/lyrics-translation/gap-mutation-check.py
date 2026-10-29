#!/usr/bin/env python3
"""Disable missing-row recovery in a temporary source copy, never the working tree."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
owner = root / "tweak/Sources/Shared/LyricsTranslation"
source = (owner / "AIServices.m").read_text()
before = "if (!indexes.count) { done(answer, nil); return; }"
after = "if (YES) { done(answer, nil); return; }"
if source.count(before) != 1:
    raise SystemExit("mutation anchor is not unique")
with tempfile.TemporaryDirectory(prefix="vitrine-ai-gap-mutation-") as directory:
    temporary = Path(directory)
    sources = root / "tweak/Sources"
    overlay = temporary / "tweak/Sources"
    # Only the mutated owner is copied. All other inputs point at the live checkout, and the
    # ordinary build script keeps its literal source dependencies visible to harness-plan.py.
    for relative, excluded in [
        ("", {"Shared"}), ("Shared", {"LyricsTranslation"}),
        ("Shared/LyricsTranslation", {"AIServices.m"}),
    ]:
        destination = overlay / relative
        destination.mkdir(parents=True, exist_ok=True)
        for child in (sources / relative).iterdir():
            if child.name not in excluded:
                (destination / child.name).symlink_to(child)
    mutated = overlay / "Shared/LyricsTranslation/AIServices.m"
    mutated.write_text(source.replace(before, after))
    harness = temporary / "harness/lyrics-translation"
    harness.mkdir(parents=True)
    for child in (root / "harness/lyrics-translation").iterdir():
        if child.is_file():
            (harness / child.name).symlink_to(child)
    (harness.parent / "sha256-fixture.h").symlink_to(root / "harness/sha256-fixture.h")
    environment = dict(os.environ, OUT=str(temporary / "build"))
    result = subprocess.run(
        ["sh", str(harness / "build.sh"), "--ai-gaps-only"],
        cwd=root, env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=120,
    )
    if result.returncode == 0 or "screenshot-shaped blank-value reply" not in result.stderr:
        print(result.stdout, result.stderr)
        raise SystemExit("mutation did not fail on the incomplete-row contract")
    print("Mutation caught: disabling missing-row recovery reproduces the screenshot-shaped gap (exit 1).")
