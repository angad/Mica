#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/verify-release.sh
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
/usr/bin/ditto -c -k --sequesterRsrc --keepParent dist/Mica.app "dist/Mica-$version-universal.zip"
# Explicit allowlist: never package build caches, local battery history, pairing
# data, the parent workspace, or private machine files.
COPYFILE_DISABLE=1 /usr/bin/tar --exclude='__pycache__' --exclude='*.pyc' \
  --exclude='*.p12' --exclude='*.p8' --exclude='*.key' --exclude='.env*' \
  -czf "dist/Mica-$version-source.tar.gz" \
  Package.swift Sources Tests Resources/Info.plist Resources/AppIcon.icns \
  scripts README.md LICENSE CONTRIBUTING.md SECURITY.md CHANGELOG.md VALIDATION.md docs .github .gitignore
(
  cd dist
  /usr/bin/shasum -a 256 "Mica-$version-universal.zip" "Mica-$version-source.tar.gz" \
    > "Mica-$version-SHA256SUMS.txt"
)
print "Release archives and checksums are in dist/."
