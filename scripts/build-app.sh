#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
if [[ "$configuration" != "release" && "$configuration" != "debug" ]]; then
  echo 'Usage: scripts/build-app.sh [release|debug]' >&2
  exit 1
fi
build_directory="${TOKENISLAND_BUILD_DIR:-${TMPDIR:-/tmp}/TokenIsland-build-$(id -u)}"
mkdir -p "$build_directory"
export CLANG_MODULE_CACHE_PATH="$build_directory/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_directory/swift-module-cache"
swift build -c "$configuration" --disable-sandbox --scratch-path "$build_directory" --cache-path "$build_directory/swiftpm-cache"
binary_directory="$(swift build -c "$configuration" --show-bin-path --disable-sandbox --scratch-path "$build_directory" --cache-path "$build_directory/swiftpm-cache")"
app="$build_directory/app/TokenIsland.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_directory/TokenIsland" "$app/Contents/MacOS/TokenIsland"
cp Resources/Info.plist "$app/Contents/Info.plist"
xattr -cr "$app"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
mkdir -p dist
# Sign and archive outside File Provider folders so the delivered ZIP stays clean.
ditto --norsrc --noextattr -c -k --keepParent "$app" "$PWD/dist/TokenIsland.zip"
ditto --norsrc --noextattr "$app" "$PWD/dist/TokenIsland.app"
echo "Built: $PWD/dist/TokenIsland.app"
echo "Packaged: $PWD/dist/TokenIsland.zip"
