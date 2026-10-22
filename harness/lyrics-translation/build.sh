#!/bin/sh
# build.sh: builds check.m against this checkout's Musixmatch.m, the translators and KaraokeTiming.m
# (and LocalFiles.m, which Musixmatch.m reads a local file's names from) as a Mac Catalyst binary and runs
# it, so no simulator is needed.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
mkdir -p "$HERE/build"
compile() {
    xcrun -sdk macosx clang -target arm64-apple-ios17.0-macabi -isysroot "$(xcrun --sdk macosx --show-sdk-path)" -iframework "$(xcrun --sdk macosx --show-sdk-path)/System/iOSSupport/System/Library/Frameworks" -DSecItemCopyMatching=SGLyricsTestKey -DSecItemAdd=SGLyricsTestKeyAdd -DSecItemUpdate=SGLyricsTestKeyUpdate -DSecItemDelete=SGLyricsTestKeyDelete -fobjc-arc -g -Wall -I"$SRC" "$@"
}
compile -DSGLyricsTranslationSendRequest=SGLyricsTranslationRealSendRequest -DSGLyricsTranslationSendOnce=SGLyricsTranslationRealSendOnce -DSGLyricsTranslationSendOnceUpTo=SGLyricsTranslationRealSendOnceUpTo -c "$SRC/Shared/LyricsTranslation/DeepL.m" -o "$HERE/build/DeepL.o"
compile -DSG_LYRICS_TEST_STORE \
    "$HERE/check.m" "$SRC/Shared/LyricsSources/Musixmatch.m" "$SRC/Shared/LyricsTranslation/LyricsTranslation.m" \
    "$HERE/build/DeepL.o" "$SRC/Shared/LyricsTranslation/BingTranslate.m" "$SRC/Shared/LyricsTranslation/GoogleTranslate.m" "$SRC/Shared/LyricsTranslation/OpenAITranslate.m" \
    "$SRC/Redesigned/Lyrics/AutoTranslation.m" "$SRC/Shared/LyricsTranslation/ConnectionTest.m" "$SRC/Shared/LyricsTranslation/ClaudeTranslate.m" "$SRC/Shared/LyricsTranslation/AIServices.m" \
    "$SRC/Shared/LyricsTranslation/SavedTranslations.m" "$SRC/Shared/LyricsTranslation/TranslatedTitles.m" \
    "$SRC/Shared/Lyrics/KaraokeTiming.m" "$SRC/Core/SGLocalize.m" "$SRC/Shared/AdBlock/Protobuf.m" "$SRC/Shared/LocalFiles/LocalFiles.m" \
    -framework NaturalLanguage -framework UIKit -framework CoreGraphics -framework Security -framework Foundation -o "$HERE/build/check"
"$HERE/build/check" "$@"
