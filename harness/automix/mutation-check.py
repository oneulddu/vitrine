#!/usr/bin/env python3
"""Break each safety boundary in a temporary copy; the real harness must reject it."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = root / "tweak/Sources/Shared/AutoMix/SGTransitionFacts.m"
original = source.read_text()
mutations = [
    ("remote-device", '![input[@"local"] boolValue] || ', "",
     "FAIL: remote device must not advertise local blending"),
    ("incomplete Automix metadata",
     "(hasAutomixMetadata(from) || hasAutomixMetadata(to))",
     '(from[@"automix.mode"] || to[@"automix.mode"])',
     "FAIL: Automix cue/tempo without mode must not invent Crossfade"),
]
for name, guard, replacement, failure in mutations:
    if original.count(guard) != 1:
        raise SystemExit(f"{name} guard is not unique")
    with tempfile.TemporaryDirectory(prefix="automix-mutation-") as work:
        mutant = Path(work) / "SGTransitionFacts.m"
        mutant.write_text(original.replace(guard, replacement, 1))
        result = subprocess.run(
            ["sh", str(root / "harness/automix/check.sh")],
            env={**os.environ, "FACTS_SOURCE": str(mutant)},
            text=True, capture_output=True,
        )
        output = result.stdout + result.stderr
        if result.returncode == 0 or failure not in output:
            raise SystemExit(f"{name} mutation did not fail at its contract:\n" + output)
    print(f"PASS: breaking {name} fails the real harness")
