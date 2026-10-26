#!/usr/bin/env python3
"""Check the engine executable's short-input contract without running DSP checks."""

import pathlib
import subprocess
import sys
import tempfile
import wave


def main():
    executable = pathlib.Path(sys.argv[1]).resolve()
    cases = [
        ("full", 48000, 20, 960000),
        ("full", 240000, 20, 960000),
        ("full", 959999, 20, 960000),
        ("stress", 48000, 5, 240000),
        ("stress", 239999, 5, 240000),
    ]
    with tempfile.TemporaryDirectory(prefix="audio-effects-input-") as directory:
        root = pathlib.Path(directory)
        for mode, frames, minimum_seconds, minimum_frames in cases:
            song = root / f"{mode}-{frames}.wav"
            output = root / f"{mode}-{frames}-out"
            with wave.open(str(song), "wb") as fixture:
                fixture.setparams((2, 2, 48000, 0, "NONE", "not compressed"))
                fixture.writeframes(b"\0" * (frames * 4))
            command = [str(executable), str(song), str(output)]
            if mode == "stress":
                command.append("stress")
            result = subprocess.run(command, capture_output=True, text=True, timeout=120)
            expected = (
                f"input too short: {mode} checks require at least {minimum_seconds} s "
                f"({minimum_frames} frames at 48000 Hz); decoded {frames} frames "
                f"({frames / 48000:.6f} s)\n"
            )
            if (result.returncode != 2 or result.stderr != expected
                    or result.stdout or output.exists()):
                print(f"FAILED: {mode}, {frames} frames: expected clean rejection "
                      f"with exit 2; got exit {result.returncode}", file=sys.stderr)
                print(result.stdout + result.stderr, file=sys.stderr)
                return 1
    print("all passed: 5 short-input cases rejected before checks or output creation")
    return 0


if __name__ == "__main__":
    sys.exit(main())
