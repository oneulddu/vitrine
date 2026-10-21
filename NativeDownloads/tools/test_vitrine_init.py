"""Run the production Vitrine init ownership fixture on an already booted simulator."""
from pathlib import Path
import argparse
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--build-only", action="store_true", help="Compile without starting or using a simulator")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
out = root / "build/vitrine-init"
out.mkdir(parents=True, exist_ok=True)
sdk = subprocess.check_output(
    ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
sources = [
    "src/DownloadSettingsUI.m", "src/Diagnostics.m", "src/DiagnosticTrace.m",
    "src/NativeKeyTrace.m", "src/WireProto.m", "src/Localization.m",
    "tests/trace_platform_stub.m", "tests/SettingsFixtureActions.m", "tests/vitrine_init.m",
]
binary = out / "vitrine-init"
subprocess.run([
    "xcrun", "clang", "-target", "arm64-apple-ios16.1-simulator", "-isysroot", sdk,
    "-fobjc-arc", "-std=gnu11", "-I" + str(root / "src"),
    *[str(root / source) for source in sources],
    "-framework", "UIKit", "-framework", "Foundation", "-framework", "CoreGraphics", "-o", str(binary),
], check=True)
subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none", str(binary)], check=True)
if not args.build_only:
    subprocess.run(["xcrun", "simctl", "spawn", "booted", str(binary)], check=True)
