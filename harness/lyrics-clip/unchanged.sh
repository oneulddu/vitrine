#!/bin/sh
# Compatibility entry point: geometry now intentionally differs from beta.23. Assert the visible-frame
# contract instead of requiring the incorrect centre-crop layout to remain pixel-identical.
set -e
exec sh "$(dirname "$0")/regression.sh"
