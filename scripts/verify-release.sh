#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
codesign --verify --deep --strict dist/Mica.app
python3 - <<'PY'
from pathlib import Path
import plistlib, re, subprocess
app = Path('dist/Mica.app')
binary = app / 'Contents/MacOS/Mica'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
required = {'arm64', 'x86_64'}
arches = set(subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split())
assert arches == required, f'Universal release required; found {arches}'
minimum = info['LSMinimumSystemVersion']
loads = subprocess.check_output(['otool', '-arch', 'all', '-l', str(binary)], text=True)
versions = re.findall(r'^\s*minos\s+(\S+)', loads, re.M)
assert len(versions) == 2 and all(v == minimum for v in versions), (minimum, versions)
dependencies = subprocess.check_output(['otool', '-arch', 'all', '-L', str(binary)], text=True)
assert '/opt/homebrew/' not in dependencies and '/Users/' not in dependencies
for library in (app / 'Contents/Frameworks').glob('*.dylib'):
    contained = set(subprocess.check_output(['lipo', '-archs', str(library)], text=True).split())
    assert required <= contained, f'{library.name} lacks a release architecture: {contained}'
source_info = plistlib.loads(Path('Resources/Info.plist').read_bytes())
assert info['CFBundleShortVersionString'] == source_info['CFBundleShortVersionString']
assert info['CFBundleVersion'] == source_info['CFBundleVersion']
print(f'Mica {info["CFBundleShortVersionString"]}: universal, minimum macOS {minimum}, signature and dependencies verified.')
PY
