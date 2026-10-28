#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_directory="${TOKENISLAND_BUILD_DIR:-${TMPDIR:-/tmp}/TokenIsland-build-$(id -u)}"
mkdir -p "$build_directory"
export CLANG_MODULE_CACHE_PATH="$build_directory/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_directory/swift-module-cache"
test_command=(swift test --disable-sandbox --scratch-path "$build_directory" --cache-path "$build_directory/swiftpm-cache")
# Some Command Line Tools distributions ship TestingMacros without registering it.
swift_binary="$(xcrun --find swiftc)"
testing_plugin="$(dirname "$swift_binary")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$testing_plugin" ]]; then
  test_command+=(-Xswiftc -load-plugin-library -Xswiftc "$testing_plugin")
fi
"${test_command[@]}"
