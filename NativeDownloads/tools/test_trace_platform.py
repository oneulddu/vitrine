"""Test production TracePlatform notifications on an already booted simulator."""
from pathlib import Path
import argparse
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--build-only", action="store_true",
                    help="Compile without starting or using a simulator")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
out = root / "build/trace-platform"
out.mkdir(parents=True, exist_ok=True)
sdk = subprocess.check_output(
    ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
binary = out / "trace-platform-notifications"
subprocess.run([
    "xcrun", "clang", "-target", "arm64-apple-ios16.1-simulator", "-isysroot", sdk,
    "-fobjc-arc", "-std=gnu11", "-I" + str(root / "src"),
    str(root / "src/TracePlatform.m"), str(root / "tests/trace_platform_notifications.m"),
    "-framework", "UIKit", "-framework", "Foundation",
    "-framework", "AVFAudio", "-framework", "Network", "-o", str(binary),
], check=True, timeout=120)
subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none", str(binary)],
               check=True, timeout=30)
if not args.build_only:
    subprocess.run(["xcrun", "simctl", "spawn", "booted", str(binary)],
                   check=True, timeout=30)
