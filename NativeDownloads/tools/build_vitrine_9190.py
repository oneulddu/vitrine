"""Build the guarded SpotifyAudioProbe overlay for the supplied Vitrine 9.1.90 IPA."""
import argparse
import hashlib
import json
import os
import plistlib
import subprocess
import tempfile
from pathlib import Path
from zipfile import ZipFile

from patch_imports import patch as patch_audio_imports
from patch_native_restrictions import patch as patch_limits, guard_header, limits_header, layout
from patch_key_request_mode import patch as patch_key_mode, key_header
from patch_native_trace import patch as patch_native_trace,header as native_trace_header

ROOT = Path(__file__).resolve().parents[1]
UUID = bytes.fromhex("fbce22c17e1b3e0d9be866ff9291943e")
SOURCE_FILES = [
    "AudioProbe.c", "Diagnostics.m", "Localization.m", "CaptureRing.c",
    "AVAudioHooks.m", "SourceGraph.c", "OfflineFlags.m", "WireProto.m",
    "OfflineConfig.m", "TrackJournal.m", "NativeErrorLog.m", "PlayerTrace.m",
    "NativeOffline.m", "TrackDownload.m", "AudioProbeUI.m", "DownloadSettingsUI.m",
    "EncodedAudio.m", "AlbumMetadata.m", "SupportLog.m", "DownloadCompatibility.m", "OfflineDevices.m",
    "DiagnosticTrace.m", "TracePlatform.m", "NativeKeyTrace.m",
]


def run(*command):
    subprocess.run([str(part) for part in command], check=True)


def prepare_native(native):
    """Validate every patch site on copies; never modify the supplied binary."""
    if layout(native)[3] != UUID:
        raise ValueError("Unsupported Spotify 9.1.90 executable UUID")
    patched, audio = patch_audio_imports(native)
    patched, limits = patch_limits(patched)
    patched, key = patch_key_mode(patched, runtime_selectable=False)
    patched, native_trace = patch_native_trace(patched)
    key["implementation"] = "verified static observation boundary restores fixed w2=0 before the original indirect call"
    key["configuration_source"] = "verified_static_trace_argument"
    return patched, audio, limits, key, native_trace


def read_input(source, require_vitrine=True):
    with ZipFile(source) as archive:
        if len(archive.namelist()) != len(set(archive.namelist())):
            raise ValueError("Duplicate ZIP members are not supported")
        info = plistlib.loads(archive.read("Payload/Spotify.app/Info.plist"))
        if info.get("CFBundleShortVersionString") != "9.1.90":
            raise ValueError("Expected Spotify 9.1.90")
        if info.get("CFBundleExecutable") != "Spotify":
            raise ValueError("Unexpected Spotify executable name")
        if require_vitrine and "Payload/Spotify.app/Frameworks/spotifyglass.dylib" not in archive.namelist():
            raise ValueError("Expected Vitrine's spotifyglass.dylib")
        if "Payload/Spotify.app/Frameworks/SpotifyAudioProbe.dylib" in archive.namelist():
            raise ValueError("Pixie is already installed")
        native = archive.read("Payload/Spotify.app/Spotify")
    return native, prepare_native(native)


def require_separate_output(source, output):
    if source == output or (output.exists() and source.samefile(output)):
        raise ValueError("Input and output IPA must be separate files")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--vitrine-dylib", type=Path, help="Vitrine rebuilt from the local sources")
    parser.add_argument("--fixed-key-mode-zero", action="store_true", help="Recovery rollback: use the direct mode-0 instruction from the last working build, without the runtime selector")
    parser.add_argument("--check-input", action="store_true",
                        help="Validate a decrypted source IPA without requiring Vitrine or writing output")
    parser.add_argument("--output", type=Path, default=ROOT / "outputs/pixie-9.1.90/Spotify-9.1.90-Pixie.ipa")
    args = parser.parse_args()
    source = args.ipa.resolve()
    output = args.output.resolve()
    if not source.is_file():
        parser.error("Input IPA not found")
    require_separate_output(source, output)
    # Check version, UUID, encryption, instructions, bindings and all caves first.
    native, (patched, audio, limits, key, native_trace) = read_input(
        source, require_vitrine=not args.check_input)
    if args.check_input:
        print(f"Pixie input accepted: Spotify 9.1.90, UUID {UUID.hex()}; all patch guards passed")
        return
    vitrine = args.vitrine_dylib.resolve() if args.vitrine_dylib else None
    if vitrine:
        run("codesign", "--verify", "--strict", vitrine)
        run("xcrun", "dyld_info", "-validate_only", vitrine)
        if b"showAlbumShuffle:play:download:add:playColor:" not in vitrine.read_bytes():
            raise RuntimeError("The rebuilt Vitrine lacks the album action row")
    if (ROOT / "src/NativeRestrictionsPatch.h").read_text() != guard_header():
        raise RuntimeError("Native restriction header is out of sync")
    if (ROOT / "src/OfflineLimits.h").read_text() != limits_header():
        raise RuntimeError("Offline limits header is out of sync")
    if (ROOT / "src/NativeKeyModePatch.h").read_text() != key_header():
        raise RuntimeError("Native key-mode header is out of sync")
    if (ROOT / "src/NativeTracePatch.h").read_text() != native_trace_header():
        raise RuntimeError("Native trace header is out of sync")

    executable = "Payload/Spotify.app/Spotify"
    output.parent.mkdir(parents=True, exist_ok=True)
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
    with tempfile.TemporaryDirectory(prefix="vitrine-9190-") as temporary:
        temporary = Path(temporary)
        if vitrine:
            staged_vitrine = temporary / "spotifyglass.dylib"
            staged_vitrine.write_bytes(vitrine.read_bytes())
            # Theos links this manual hook to its jailbreak framework path.
            # The supplied sideload IPA already bundles the same framework.
            dependencies = subprocess.check_output(["otool", "-L", str(staged_vitrine)], text=True)
            substrate = "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate"
            if substrate in dependencies:
                run("install_name_tool", "-change", substrate,
                    "@rpath/CydiaSubstrate.framework/CydiaSubstrate", staged_vitrine)
            run("codesign", "--force", "--sign", "-", "--timestamp=none", staged_vitrine)
            run("codesign", "--verify", "--strict", staged_vitrine)
            run("xcrun", "dyld_info", "-validate_only", staged_vitrine)
            vitrine = staged_vitrine
        companion = temporary / "SpotifyAudioProbe.dylib"
        run("xcrun", "clang", "-dynamiclib", "-arch", "arm64", "-target", "arm64-apple-ios15.0",
            "-isysroot", sdk, "-fobjc-arc", "-std=gnu11", "-O2", "-fvisibility=hidden",
            "-Wall", "-Wextra", "-Wno-unused-parameter", "-Wno-nullability-completeness",
            "-Werror=implicit-function-declaration", "-I" + str(ROOT / "src"),
            "-DSAP_ENABLE_WAV_CAPTURE=0", *(ROOT / "src" / name for name in SOURCE_FILES),
            "-framework", "AudioToolbox", "-framework", "Foundation", "-framework", "UIKit",
            "-framework", "AVFAudio", "-framework", "CoreGraphics", "-framework", "AVFoundation",
            "-framework", "CoreMedia", "-framework", "Network", "-Wl,-install_name,@rpath/SpotifyAudioProbe.dylib", "-o", companion)
        run("codesign", "--force", "--sign", "-", "--timestamp=none", companion)
        run("codesign", "--verify", "--strict", companion)
        run("xcrun", "dyld_info", "-validate_only", companion)
        binary = temporary / "Spotify"
        binary.write_bytes(native)
        # Preserve cyan's existing application entitlements, including App Groups.
        entitlements = subprocess.check_output(["ldid", "-e", str(binary)])
        original_entitlements = plistlib.loads(entitlements)
        entitlement_file = temporary / "entitlements.plist"
        entitlement_file.write_bytes(entitlements)
        binary.write_bytes(patched)
        binary.chmod(0o755)
        run("codesign", "--force", "--sign", "-", "--timestamp=none",
            "--entitlements", entitlement_file, binary)
        run("codesign", "--verify", "--strict", binary)
        if plistlib.loads(subprocess.check_output(["ldid", "-e", str(binary)])) != original_entitlements:
            raise RuntimeError("Spotify entitlements changed during overlay signing")
        run("xcrun", "dyld_info", "-validate_only", binary)
        imports = subprocess.check_output(["xcrun", "dyld_info", "-imports", str(binary)], text=True)
        for change in audio["changes"]:
            matches = [line for line in imports.splitlines() if change["symbol"] in line]
            if not matches or not all("SpotifyAudioProbe" in line for line in matches):
                raise RuntimeError(f"Audio import not redirected: {change['symbol']}")
        # Only publish a complete, integrity-checked archive on the same filesystem.
        with tempfile.TemporaryDirectory(prefix=".pixie-overlay-", dir=output.parent) as staging:
            staged_output = Path(staging) / "result.ipa"
            with ZipFile(source) as original, ZipFile(staged_output, "w", allowZip64=True) as result:
                for member in original.infolist():
                    replacement = binary.read_bytes() if member.filename == executable else vitrine.read_bytes() if vitrine and member.filename == "Payload/Spotify.app/Frameworks/spotifyglass.dylib" else original.read(member.filename)
                    result.writestr(member, replacement)
                result.write(companion, "Payload/Spotify.app/Frameworks/SpotifyAudioProbe.dylib")
            with ZipFile(staged_output) as check:
                if check.testzip() is not None:
                    raise RuntimeError("IPA ZIP integrity check failed")
            with staged_output.open("rb") as stream:
                digest = hashlib.sha256()
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
                os.fsync(stream.fileno())
            os.replace(staged_output, output)

    print(json.dumps({"output": str(output), "sha256": digest.hexdigest(),
                      "spotify_uuid": UUID.hex(), "audio_imports": audio,
                      "native_limits": limits, "key_request_mode": key, "native_observation": native_trace}, indent=2))


if __name__ == "__main__":
    main()
