"""Break one rule in a copy of tweak/Sources for faces-more-check.sh, never in the working tree.

    faces-more-mutation.py <copy of tweak/Sources> faces-cap|faces-hidden|more-mask
"""
from pathlib import Path
import sys

root, mode = Path(sys.argv[1]), sys.argv[2]


def replace(rel, old, new):
    path = root / rel
    source = path.read_text()
    if source.count(old) != 1:
        raise SystemExit(f"{mode}: anchor changed in {rel}: {old}")
    path.write_text(source.replace(old, new))


if mode == "faces-cap":
    # Four faces where the spec allows three.
    replace("Redesigned/Kit/SGRHeaderInfo.m", "static const NSUInteger kMaxFaces = 3;", "static const NSUInteger kMaxFaces = 4;")
elif mode == "faces-hidden":
    # A picture landing in a view hidden since the header's pass counted as a face.
    replace("Redesigned/Kit/SGRHeaderInfo.m", "        if (!parent || !shownIn(source, parent)) continue;\n", "")
elif mode == "more-mask":
    # No colour layer and mask for a baked glyph: every glyph only given the tint.
    replace("Redesigned/Album/AlbumRows.x", "    if (template) {\n        BOOL ours", "    if (YES) {\n        BOOL ours")
else:
    raise SystemExit(f"unknown mutation: {mode}")
