#!/bin/sh
# Builds the Music Haptics harnesses for the Mac: SGMusicAnalyzer.m as the tweak compiles it under main.m, and
# Native iOS's pure steps (SGHapticTrack.m and the protobuf reader) under track.m.
set -e
cd "$(dirname "$0")"
mkdir -p build
xcrun clang -fobjc-arc -O2 -Wall -Werror -I ../../tweak/Sources -framework Foundation -framework AudioToolbox \
    main.m ../../tweak/Sources/Shared/Haptics/SGMusicAnalyzer.m -o build/haptics
xcrun clang -fobjc-arc -O2 -Wall -Werror -I ../../tweak/Sources -framework Foundation \
    track.m ../../tweak/Sources/Shared/Haptics/SGHapticTrack.m ../../tweak/Sources/Shared/AdBlock/Protobuf.m -o build/track
xcrun clang -fobjc-arc -O1 -g -Wall -Werror -fsanitize=thread -I ../../tweak/Sources -framework Foundation \
    ring.m -o build/ring
echo "built build/haptics, build/track and build/ring"
