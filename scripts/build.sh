#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/mica-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/mica-swift-cache"
architectures=("$(uname -m)")
if [[ "${1:-}" == "--universal" ]]; then architectures=(arm64 x86_64); fi
binaries=()
for architecture in "${architectures[@]}"; do
  build_path="$PWD/.build/native-$architecture"
  runtime_options=()
  runtime_directory="${MICA_INTEL_RUNTIME_DIR:-$PWD/.build/intel-runtime/macosx}"
  if [[ "$architecture" == "x86_64" && -f "$runtime_directory/libswiftCompatibility56.a" ]]; then
    runtime_options=(-Xlinker "$runtime_directory/libswiftCompatibility56.a" -Xlinker "$runtime_directory/libswiftCompatibilityPacks.a")
  fi
  swift build --build-system native --triple "$architecture-apple-macosx12.3" \
    --scratch-path "$build_path" --cache-path "$PWD/.build/cache" --manifest-cache local \
    -c release --disable-sandbox "${runtime_options[@]}"
  binaries+=("$build_path/$architecture-apple-macosx/release/Mica")
done
app_bundle="$PWD/dist/Mica.app"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources" "$app_bundle/Contents/Frameworks"
if (( ${#binaries[@]} > 1 )); then
  lipo -create "${binaries[@]}" -output "$app_bundle/Contents/MacOS/Mica.new"
else
  cp "${binaries[1]}" "$app_bundle/Contents/MacOS/Mica.new"
fi
mv -f "$app_bundle/Contents/MacOS/Mica.new" "$app_bundle/Contents/MacOS/Mica"
cp Resources/Info.plist "$app_bundle/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$app_bundle/Contents/Resources/"; fi
cp LICENSE "$app_bundle/Contents/Resources/LICENSE.txt"
cp docs/SWIFT-RUNTIME-LICENSE.txt "$app_bundle/Contents/Resources/Swift-Runtime-LICENSE.txt"
# Bundle back-deployed Swift runtime libraries required on older macOS releases.
xcrun swift-stdlib-tool --copy --scan-executable "$app_bundle/Contents/MacOS/Mica" \
  --destination "$app_bundle/Contents/Frameworks" --platform macosx --sign -
codesign --force --deep --sign - "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
print "Built: $app_bundle"
