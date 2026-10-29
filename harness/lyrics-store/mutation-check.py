"""Remove each persistence rule in an isolated source copy; the real harness must fail."""
import os
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / "tweak/Sources/Shared/Lyrics/LyricsStore.m").read_text()
mutations = [
    ("translations", 'if (translation) record[@"translation"] = translation;',
     '(void)translation;', 'record[@"lines"][0][@"backing"][@"translation"]'),
    ("credit-links", 'if (links) record[@"creditLinks"] = links;',
     '(void)links;', 'providerRecord[@"creditLinks"][0][@"url"]'),
    ("rejected-load-credit", 'done(lines, credit, metadata);',
     'if (metadata) SGLyricsNoteCredit(metadata);\n            done(lines, credit, metadata);',
     'SGLyricsCreditLinks(@"Linked provider").firstObject.url.absoluteString'),
]
for name, old, new, assertion in mutations:
    if source.count(old) != 1:
        raise SystemExit(f"{name}: mutation target is not unique")
    with tempfile.TemporaryDirectory(prefix="fix-offline-lyrics-mutation.", dir="/tmp") as directory:
        folder = pathlib.Path(directory)
        mutant = folder / "LyricsStore.m"
        mutant.write_text(source.replace(old, new))
        build = folder / "build"
        build.mkdir()
        env = dict(os.environ, LYRICS_STORE_SOURCE=str(mutant), HARNESS_BUILD_DIR=str(build),
                   TMPDIR=directory)
        run = subprocess.run(["sh", str(root / "harness/lyrics-store/build.sh")],
                             env=env, text=True, capture_output=True)
        if run.returncode == 0 or assertion not in run.stderr:
            print(run.stdout, end="")
            print(run.stderr, end="")
            raise SystemExit(f"{name}: did not fail at the expected assertion")
        print(f"{name}: rejected by the persistence check")
