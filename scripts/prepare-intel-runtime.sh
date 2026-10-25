#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# Some Apple Silicon-only CLT distributions omit the Intel back-deployment
# archives. Extract them from a pinned, official, Apple-notarized Swift package.
# The 1.65 GiB package is temporary; nothing is installed on the system.
working_directory=$(mktemp -d "${TMPDIR:-/tmp}/mica-runtime.XXXXXX")
trap 'rm -rf "$working_directory"' EXIT
package="$working_directory/swift.pkg"
url="https://download.swift.org/swift-6.2-release/xcode/swift-6.2-RELEASE/swift-6.2-RELEASE-osx.pkg"
expected="9eac4a13500c7a6dedfd90814fd31c17af2efc38150137b56b70bf5f44b2d64b"
curl --fail --location --output "$package" "$url"
print -r -- "$expected  $package" | shasum -a 256 -c -
signature=$(/usr/sbin/pkgutil --check-signature "$package")
[[ "$signature" == *"Swift Open Source (V9AUD2URP3)"* ]] || { print -u2 "Unexpected package signer"; exit 1; }
[[ "$signature" == *"trusted by the Apple notary service"* ]] || { print -u2 "Package notarization was not verified"; exit 1; }
/usr/sbin/pkgutil --expand-full "$package" "$working_directory/expanded"
payload="$working_directory/expanded/swift-6.2-RELEASE-osx-package.pkg/Payload"
target="$PWD/.build/intel-runtime/macosx"
mkdir -p "$target"
cp "$payload"/usr/lib/swift/macosx/libswiftCompatibility*.a "$target/"
lipo -archs "$target/libswiftCompatibility56.a"
print "Intel compatibility archives are ready in .build/intel-runtime/macosx."
