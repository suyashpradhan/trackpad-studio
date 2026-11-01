#!/bin/zsh
set -eu
cd "${0:A:h:h}"
# Select CLT locally; do not change xcode-select or accept licenses automatically.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
if [[ "${1:-}" == "test" && -x /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    exec "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" "$@" --disable-sandbox --build-system native --scratch-path .build-tests
fi
exec /usr/bin/swift "$@" --disable-sandbox
