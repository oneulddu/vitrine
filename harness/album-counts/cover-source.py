"""Compile the production preferences owner without its unrelated UIKit renderer."""
import pathlib
import sys

src, output = map(pathlib.Path, sys.argv[1:])
header = (src / "Redesigned/Kit/SGRHeaderInfo.h").read_text()
impl = (src / "Redesigned/Kit/SGRHeaderInfo.m").read_text()
declarations = header[header.index("#define SGRKeyFullBleedCovers"):header.index("@interface")]
body = impl[impl.index("BOOL SGRPageFullCover("):impl.index("// The text kSide")]
# The slice also carries the header's other small helpers (the Play colour gate); this check calls none of them.
output.write_text('#import "Core/SGPrefs.h"\n#pragma clang diagnostic ignored "-Wunused-function"\n' + declarations + body)
