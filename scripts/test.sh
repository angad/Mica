#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/mica-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/mica-swift-cache"
swift_binary="$(xcrun --find swiftc)"
developer_directory="$(xcode-select -p)"
extra_options=()
# Standalone CLT and full Xcode keep Swift Testing in different framework paths.
for directory in "${swift_binary:h:h:h}/Library/Developer/Frameworks" \
  "$developer_directory/Platforms/MacOSX.platform/Developer/Library/Frameworks" \
  "$developer_directory/Library/Frameworks"; do
  if [[ -d "$directory/Testing.framework" ]]; then
    extra_options+=(-Xswiftc -F -Xswiftc "$directory" -Xlinker -F -Xlinker "$directory" -Xlinker -rpath -Xlinker "$directory")
    break
  fi
done
testing_plugin="${swift_binary:h:h}/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$testing_plugin" ]]; then
  extra_options+=(-Xswiftc -load-plugin-library -Xswiftc "$testing_plugin")
fi
swift test --build-system native --scratch-path .build/tests --cache-path .build/cache \
  --manifest-cache local -c release --disable-sandbox "${extra_options[@]}"
