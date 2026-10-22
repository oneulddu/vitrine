"""Focused host regression: production download, selected-menu and library paths."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="pixie-single-track-") as temporary:
    binary = Path(temporary) / "track_download"
    sources = [
        "src/WireProto.m", "src/PlayerTrace.m", "src/TrackDownload.m",
        "src/TrackLibrary.m", "src/TrackMenu.m", "tests/track_download.m",
        "src/Diagnostics.m", "src/Localization.m", "src/DiagnosticTrace.m",
        "src/NativeKeyTrace.m", "tests/trace_platform_stub.m",
    ]
    subprocess.run([
        "xcrun", "clang", "-arch", "arm64", "-fobjc-arc", "-std=gnu11", "-O1", "-g",
        "-Isrc", "-DSAP_TESTING", "-fsanitize=address,undefined", *sources,
        "-framework", "Foundation", "-o", str(binary),
    ], cwd=root, check=True, timeout=60)
    subprocess.run([str(binary), "-AppleLanguages", "(en)"], cwd=root, check=True, timeout=30)
