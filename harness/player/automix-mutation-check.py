#!/usr/bin/env python3
"""One rule of each AutoMix area broken once, in a copy of the sources: automix-check.sh must fail on the check that
guards it.

    THEOS=$HOME/theos python3 harness/player/automix-mutation-check.py [--only NAME]
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCES = HERE.parent.parent / "tweak" / "Sources"
MIX = "Redesigned/Player/PlayerMix.x"
QUEUE = "Redesigned/Player/PlayerQueue.m"
PREVIEW = "Shared/AutoMix/AutoMixPreview.m"

# (file, what is broken, the text replaced, its replacement, the check that must say WRONG)
MUTATIONS = [
    (MIX, "the progress bar draws a window whose times are unknown",
     "BOOL outgoing = facts.timesKnown && SGRMixTrackIs(",
     "BOOL outgoing = SGRMixTrackIs(",
     "progress unknown times draw nothing"),
    (QUEUE, "the queue names a blend into a song that is not the first row",
     "\n        || !SGRMixTrackIs(next, facts.toURI, facts.toUID)) return nil;",
     ") return nil;",
     "queue facts for another pair"),
    (MIX, "a seek back leaves the cover hidden under a stage that stopped moving",
     '[self stop:@"a seek back before the window" done:NO];',
     "[_link invalidate];\n            _link = nil;\n            _view = nil;",
     "artwork a seek back hands the cover back"),
    (MIX, "a stage keeps the cover hidden while the player is not seen, as long as it is in a window",
     "return !sg_artworkOn || !seen(view) ||",
     "return !sg_artworkOn || !view.window ||",
     "artwork a hidden player hands the cover back"),
    (MIX, "a stage keeps its plan after the facts named another next song",
     "            if (_plan != sg_facts) {\n                [self stop:@\"the facts changed\" done:NO];\n                return;\n            }\n",
     "",
     "artwork a new next song hands the cover back"),
    (PREVIEW, "the preview's overlap ignores Blend length",
     "length = off ? 0 : _shown.seconds;",
     "length = off ? 0 : 5;",
     "preview crossfade 1 s, changed in Spotify's settings"),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", choices=[mutation[1] for mutation in MUTATIONS], action="append",
                        help="rerun a failed mutation without repeating valid passes")
    only = parser.parse_args().only
    failed = False
    for source, name, original, broken, guard in MUTATIONS:
        if only and name not in only:
            continue
        with tempfile.TemporaryDirectory(prefix="player-automix-mutation.") as work:
            sources = Path(work) / "Sources"
            shutil.copytree(SOURCES, sources)
            target = sources / source
            text = target.read_text()
            if text.count(original) != 1:
                print("mutation %r: the text to break is not in %s once" % (name, source))
                failed = True
                continue
            target.write_text(text.replace(original, broken))
            env = dict(os.environ, SRC=str(sources))
            env.pop("SHOTS", None)  # Never overwrite deliverable screenshots with a deliberately broken build.
            run = subprocess.run(["sh", str(HERE / "automix-check.sh")], env=env,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            caught = run.returncode != 0 and any(guard in line and line.endswith("-- WRONG") for line in run.stdout.splitlines())
            print("mutation %r: %s" % (name, "caught by \"%s\"" % guard if caught else "NOT CAUGHT"), flush=True)
            if not caught:
                print(run.stdout, flush=True)
                failed = True
    print("automix mutations: %s" % ("FAIL" if failed else "PASS"))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
