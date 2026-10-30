#!/usr/bin/env python3
"""Break one rule of the picture-aware photo in a copy of its source, for photo-check.sh to see the checks reject it.

    photo-mutation.py <mutant> <file>

exclusion takes a copy of Redesigned/Kit/SGRCoverRead.m; stale takes the generated copy of
Redesigned/Artist/ArtistHeader.x. The working tree is never touched. Each mutant has to match its text exactly as many
times as it says, so a rewrite of the source fails here rather than mutating nothing.
"""

import sys
from pathlib import Path

MUTANTS = {
    # The foot keeps the pixels inside the faces.
    "exclusion": [("            if (inAny(faces, x, y)) continue;\n", "", 1)],
    # The hero takes the read of a photo it no longer shows.
    "stale": [("if (!hero || hero->_picture.image != image) return;", "if (!hero) return;", 1)],
}


def main():
    mutant, path = sys.argv[1], Path(sys.argv[2])
    text = path.read_text()
    for old, new, count in MUTANTS[mutant]:
        found = text.count(old)
        if found != count:
            sys.exit(f"[harness] FAIL mutant {mutant}: {old!r} found {found} times in {path}, not {count}")
        text = text.replace(old, new)
    path.write_text(text)


if __name__ == "__main__":
    main()
