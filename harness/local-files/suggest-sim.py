#!/usr/bin/env python3
"""Run real editor/review with URLProtocol fixtures; screenshots and persistence/presentation mutations."""
import os
import pathlib
import shutil
import subprocess
import tempfile
import threading
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]
LOCAL = ROOT / "tweak/Sources/Shared/LocalFiles"
SHOTS = ROOT / ".mixdog/review-shots/suggest-info"

def main():
    import json
    devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
    runtime, device = next((runtime, d) for runtime, group in devices["devices"].items() for d in group
                           if d["isAvailable"] and "iPhone" in d["name"])
    # A dedicated clean device avoids inheriting another harness's accessibility/runtime state.
    udid = subprocess.check_output(["xcrun", "simctl", "create", "VitrineSuggestInfo-" + uuid.uuid4().hex,
        device["deviceTypeIdentifier"], runtime], text=True).strip()
    try:
        subprocess.run(["xcrun", "simctl", "boot", udid], check=True)
        subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], check=True)
        with tempfile.TemporaryDirectory(prefix="vitrine-suggest-sim-") as temp:
            workspace = pathlib.Path(temp)
            for mode in ("baseline", "accept-writes", "save-missing", "picker-cancel", "presentation-guard"):
                sources = workspace / mode / "LocalFiles"
                shutil.copytree(LOCAL, sources)
                editor = sources / "EditInfoMenu.x"
                source = editor.read_text()
                if mode == "accept-writes":
                    old = "- (void)acceptInfo:(NSDictionary<NSString *, NSString *> *)names cover:(UIImage *)cover {"
                    source = source.replace(old, old + "\n    SGLocalFileSaveEdit(_uri, names, cover, YES);", 1)
                elif mode == "save-missing":
                    old = "SGLocalFileSaveEdit(_uri, self.names, _coverChange == SGCoverPicked ? _cover : nil, _coverChange != SGCoverRemoved);"
                    source = source.replace(old, "(void)self.names;", 1)
                elif mode == "picker-cancel":
                    old = "- (void)pickCoverFromFiles:(BOOL)files {\n    ++_infoRequest;\n    [_infoLookup cancel];\n    _findingInfo = NO;\n    _findInfoButton.enabled = YES;"
                    source = source.replace(old, "- (void)pickCoverFromFiles:(BOOL)files {", 1)
                elif mode == "presentation-guard":
                    source = source.replace("!editor.view.window || editor.presentedViewController ||",
                                            "!editor.view.window ||", 1)
                editor.write_text(source)
                out = workspace / mode / "build"
                env = dict(os.environ, THEOS=str(pathlib.Path.home() / "theos"), OUT=str(out), LOCAL=str(sources))
                subprocess.run(["sh", str(ROOT / "harness/local-files/sim/build-sim.sh")], env=env, check=True)
                subprocess.run(["xcrun", "simctl", "install", udid, str(out / "EditInfoHarness.app")], check=True)
                process = subprocess.Popen(["xcrun", "simctl", "launch", "--console-pty", udid,
                    "com.vitrine.editinfoharness", "suggest"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                timed_out = threading.Event()
                def stop_stalled():
                    timed_out.set()
                    subprocess.run(["xcrun", "simctl", "terminate", udid, "com.vitrine.editinfoharness"], check=True)
                    process.terminate()
                timer = threading.Timer(40, stop_stalled)
                timer.start()
                lines = []
                for line in process.stdout:
                    print(line, end="", flush=True)
                    lines.append(line)
                    if "[harness] SHOT " in line and mode == "baseline":
                        SHOTS.mkdir(parents=True, exist_ok=True)
                        name = line.split("[harness] SHOT ", 1)[1].strip()
                        subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", str(SHOTS / (name + ".png"))], check=True)
                process.wait(timeout=40)
                timer.cancel()
                if timed_out.is_set():
                    raise SystemExit("simulator app timed out before completing its checks")
                output = "".join(lines)
                if mode == "baseline":
                    if "[harness] PASS: 0 failed" not in output or "[harness] FAIL" in output:
                        raise SystemExit("baseline simulator contract failed")
                elif {
                    "accept-writes": "[harness] FAIL Use only fills selected fields; no overlay write",
                    "save-missing": "[harness] FAIL existing Save publishes the URI-keyed overlay",
                    "picker-cancel": "[harness] FAIL Files picker cancels lookup and re-enables Find Info",
                    "presentation-guard": "[harness] FAIL answer behind another controller is dropped and button reset",
                }[mode] not in output:
                    raise SystemExit(f"mutation did not trigger its contract check: {mode}")
                else:
                    print(f"PASS mutation {mode}: rejected")
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", "all"], check=True)
        subprocess.run(["osascript", "-e", 'tell application "Simulator" to quit'], check=True)
        subprocess.run(["xcrun", "simctl", "delete", udid], check=True)

if __name__ == "__main__":
    main()
