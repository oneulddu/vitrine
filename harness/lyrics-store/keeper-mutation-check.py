"""Remove Musixmatch provenance stamping in an isolated keeper build."""
import os
import pathlib
import shutil
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="lyrics-store-keeper-mutation.", dir="/tmp") as directory:
    source = pathlib.Path(directory) / "Sources"
    shutil.copytree(root / "tweak/Sources", source)
    keeper = source / "Shared/Lyrics/KaraokeSource.x"
    text = keeper.read_text()
    old = "if (line != kept[i]) line.translationLanguage = language;"
    if text.count(old) != 1:
        raise SystemExit("Musixmatch mutation target is not unique")
    keeper.write_text(text.replace(old, "(void)line;"))
    run = subprocess.run(["sh", str(root / "harness/lyrics-sources/state-build.sh")],
                         env=dict(os.environ, LYRICS_SOURCE_ROOT=str(source), VITRINE_STORE_ONLY="1"),
                         text=True, capture_output=True)
    if run.returncode == 0 or '[communityLines.firstObject.translationLanguage isEqual:@"en"]' not in run.stderr:
        print(run.stdout, end="")
        print(run.stderr, end="")
        raise SystemExit("Musixmatch mutation did not fail at the provenance assertion")
    print("Musixmatch: missing provenance rejected by the keeper check")
