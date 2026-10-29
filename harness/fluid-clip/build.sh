#!/bin/sh
# Builds the Fluid clip harness for the Mac: SGFluidClip.m as the tweak compiles it, and main.m; then the
# player clip's failure recovery, the policy PlayerMotion.x compiles, as recovery-check.
set -e
cd "$(dirname "$0")"
OUT=${OUT:-build}
mkdir -p "$OUT"
xcrun clang -fobjc-arc -O2 -Wno-deprecated-declarations -I ../../tweak/Sources \
    -framework Foundation -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework CoreImage \
    -framework CoreText -framework CoreGraphics -framework ImageIO -framework UniformTypeIdentifiers -framework Accelerate \
    -framework AppKit \
    main.m ../../tweak/Sources/Shared/AnimatedArtwork/SGFluidClip.m ../../tweak/Sources/Shared/LockScreenLyrics/SGLyricsClip.m \
    ../../tweak/Sources/Shared/LyricsBackground/LyricsBackground.m \
    -o "$OUT/fluid-clip"
# The player clip's recovery, as PlayerMotion.x compiles it: the policy, its steps and its bound, and the
# handover a new track begins.
python3 - ../../tweak/Sources/Redesigned/Player/PlayerMotion.x "$OUT/player-motion-recovery.inc" "$OUT/player-motion-handover.inc" <<'PY'
import pathlib
import re
import sys

lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
start = next((i for i, line in enumerate(lines) if line.startswith("static const NSUInteger kRebuildsMost")), None)
end = next((i for i, line in enumerate(lines) if line.startswith("@interface CAFilter")), None)
if start is None or end is None or end <= start:
    raise SystemExit("expected the recovery policy between kRebuildsMost and CAFilter")
pathlib.Path(sys.argv[2]).write_text("\n".join(lines[start:end]) + "\n")

source = "\n".join(lines)
found = re.findall(r"^static BOOL beginTrack\(NSString \*track\) \{\n.*?^\}$", source, re.M | re.S)
if len(found) != 1:
    raise SystemExit(f"expected one complete definition of beginTrack, found {len(found)}")
handover = re.findall(r"^static const NSTimeInterval kHandOver = [0-9.]+;$", source, re.M)
if len(handover) != 1:
    raise SystemExit(f"expected one kHandOver, found {len(handover)}")
pathlib.Path(sys.argv[3]).write_text(handover[0] + "\n\n" + found[0] + "\n")
PY
xcrun clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter -I "$OUT" recovery-check.m -framework Foundation \
    -o "$OUT/recovery-check"
"$OUT/recovery-check"
