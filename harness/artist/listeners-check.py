#!/usr/bin/env python3
"""Run the artist listeners contract and configuration-provenance mutations."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def check_case(device, enabled, hidden, expected_failure=None):
    result = subprocess.run([
        "xcrun", "simctl", "launch", "--console", "--terminate-running-process",
        device, "com.vojta.artistharness", "verify-listeners",
        "-spotifyglass.redesign.artist.listenersInAbout", enabled,
        "-spotifyglass.redesign.artist.hide.about", hidden,
        "-spotifyglass.redesign.artist.logo", "NO",
        "-spotifyglass.redesign.artist.motion", "NO"],
        capture_output=True, text=True, timeout=60)
    log = result.stdout + result.stderr
    print(log, flush=True)
    if expected_failure:
        if expected_failure not in log or "[harness] PASS artist listeners:" in log:
            raise RuntimeError("mutation did not fail its listeners contract")
    elif result.returncode or "[harness] PASS artist listeners:" not in log or "[harness] FAIL" in log:
        raise RuntimeError(f"listeners option={enabled} hideAbout={hidden} failed ({result.returncode})")


def main():
    workspace = Path(tempfile.mkdtemp(prefix="artist-listeners-"))
    device = None
    try:
        env = dict(os.environ, HARNESS_BUILD_DIR=str(workspace / "normal"))
        run("sh", str(ROOT / "harness/artist/build.sh"), env=env, cwd=ROOT)
        source = ROOT / "tweak/Sources/Redesigned/Artist/ArtistSections.x"
        text = source.read_text()
        binding = "objc_setAssociatedObject(cell, &kListenersConfigurationKey, configuration, OBJC_ASSOCIATION_RETAIN_NONATOMIC);"
        provenance = "if (!currentConfiguration(configuration, list, path)) return;"
        mutations = [
            ("unavailable", "return state.aboutPath != nil;", "return YES;",
             "listeners artist without About: expected 1 visible/accessibility representations, got 0"),
            ("reconfigure", binding,
             "if (!objc_getAssociatedObject(cell, &kListenersConfigurationKey)) " + binding,
             "listeners retained About reconfigured for new artist: expected 0 visible/accessibility representations, got 1"),
            ("stale", provenance, """if (!currentConfiguration(configuration, list, path)) {
        configuration = [SGRArtistItemConfiguration new];
        configuration.source = (UICollectionViewDiffableDataSource *)list.dataSource;
        configuration.itemIdentifier = [configuration.source itemIdentifierForIndexPath:path];
        configuration.identity = state.identityView.accessibilityIdentifier;
    }""",
             "listeners unstamped stale About cannot belong to new artist: expected 1 visible/accessibility representations, got 0"),
        ]
        for name, target, replacement, _ in mutations:
            if text.count(target) != 1:
                raise RuntimeError(f"{name} mutation target is not unique")
            mutant = workspace / f"{name}.x"
            mutant.write_text(text.replace(target, replacement))
            env.update(HARNESS_BUILD_DIR=str(workspace / name),
                       HARNESS_ARTIST_SECTIONS_SOURCE=str(mutant))
            run("sh", str(ROOT / "harness/artist/build.sh"), env=env, cwd=ROOT)

        # Boot only for the device checks, not while the builds are running.
        runtimes = json.loads(subprocess.check_output(
            ["xcrun", "simctl", "list", "runtimes", "available", "-j"], text=True))
        runtime = next(r["identifier"] for r in runtimes["runtimes"] if r["platform"] == "iOS")
        device = subprocess.check_output([
            "xcrun", "simctl", "create", "Artist listeners check",
            "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro", runtime], text=True).strip()
        run("xcrun", "simctl", "boot", device)
        run("xcrun", "simctl", "bootstatus", device, "-b")
        app = workspace / "normal/ArtistHarness.app"
        run("xcrun", "simctl", "install", device, str(app))
        for enabled, hidden in (("NO", "NO"), ("YES", "NO"), ("YES", "YES")):
            check_case(device, enabled, hidden)

        for name, _, _, expected in mutations:
            run("xcrun", "simctl", "install", device, str(workspace / f"{name}/ArtistHarness.app"))
            check_case(device, "YES", "NO", expected)
            print(f"PASS artist listeners {name} mutation killed", flush=True)
    finally:
        try:
            if device:
                # Another simulator user can shut down all devices. Do not let
                # that race prevent cleanup or obscure the failed check.
                devices = json.loads(subprocess.check_output(
                    ["xcrun", "simctl", "list", "devices", "-j"], text=True))
                state = next(d["state"] for group in devices["devices"].values()
                             for d in group if d["udid"] == device)
                if state != "Shutdown":
                    run("xcrun", "simctl", "shutdown", device)
                run("xcrun", "simctl", "delete", device)
        finally:
            shutil.rmtree(workspace)


if __name__ == "__main__":
    main()
