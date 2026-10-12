#!/bin/bash
# Builds Burnish and launches it from the build output.
#
# The app is deliberately not installed into /Applications: a copy there would freeze at
# whatever was built that day, while development keeps moving. Running from the build output
# means what you open is always what the repository currently says (see CLAUDE.md §14).
#
#   ./scripts/run.sh            Release build, then launch
#   ./scripts/run.sh debug      Debug build, then launch
#   ./scripts/run.sh --no-open  build only
#
# To keep it one click away, launch it once and then right-click its Dock icon →
# Options → Keep in Dock. That shortcut follows the build output, so it stays current.

set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="Release"
LAUNCH=true

for arg in "$@"; do
    case "$arg" in
        debug|Debug)       CONFIG="Debug" ;;
        release|Release)   CONFIG="Release" ;;
        --no-open)         LAUNCH=false ;;
        *) echo "unknown argument: $arg" >&2; exit 1 ;;
    esac
done

# Regenerate the project when the manifest is newer than it, so a changed module layout is
# never silently missing from the build.
if [ ! -d Burnish.xcodeproj ] || [ project.yml -nt Burnish.xcodeproj ]; then
    echo "==> xcodegen generate"
    xcodegen generate
fi

echo "==> building $CONFIG"
xcodebuild build \
    -scheme Burnish \
    -destination 'platform=macOS' \
    -configuration "$CONFIG" \
    CODE_SIGNING_ALLOWED=NO \
    -quiet

PRODUCTS=$(xcodebuild -scheme Burnish -destination 'platform=macOS' \
    -configuration "$CONFIG" -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}' | head -1)

APP="$PRODUCTS/Burnish.app"
[ -d "$APP" ] || { echo "build produced no app at $APP" >&2; exit 1; }

echo "==> $APP"

if [ "$LAUNCH" = true ]; then
    # Replace a running copy so you are never looking at the previous build.
    pkill -x Burnish 2>/dev/null || true
    sleep 0.5
    open "$APP"
fi
