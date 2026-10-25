#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
python3 - "$@" <<'PY'
from pathlib import Path
import argparse, plistlib, re, subprocess
parser = argparse.ArgumentParser(description='Verify a universal Mica release.')
parser.add_argument('--distribution', action='store_true', help='Require Developer ID, timestamp and hardened runtime')
parser.add_argument('--notarized', action='store_true', help='Also require a stapled ticket and Gatekeeper acceptance')
parser.add_argument('app', nargs='?', default='dist/Mica.app', type=Path)
args = parser.parse_args()
app = args.app
subprocess.run(['codesign', '--verify', '--all-architectures', '--deep', '--strict', str(app)], check=True)
binary = app / 'Contents/MacOS/Mica'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'sg.angad.Mica', 'Unexpected bundle identity'
required = {'arm64', 'x86_64'}
arches = set(subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split())
assert arches == required, f'Universal release required; found {arches}'
minimum = info['LSMinimumSystemVersion']
loads = subprocess.check_output(['otool', '-arch', 'all', '-l', str(binary)], text=True)
versions = re.findall(r'^\s*minos\s+(\S+)', loads, re.M)
assert len(versions) == 2 and all(v == minimum for v in versions), (minimum, versions)
libraries = list((app / 'Contents/Frameworks').glob('*.dylib'))
for code in [binary, *libraries]:
    dependencies = subprocess.check_output(['otool', '-arch', 'all', '-L', str(code)], text=True)
    for dependency in re.findall(r'^\s+(\S+)\s+\(', dependencies, re.M):
        assert dependency.startswith(('/System/Library/', '/usr/lib/', '@rpath/',
                                      '@loader_path/', '@executable_path/')), (code, dependency)
for library in libraries:
    contained = set(subprocess.check_output(['lipo', '-archs', str(library)], text=True).split())
    assert required <= contained, f'{library.name} lacks a release architecture: {contained}'
if args.distribution or args.notarized:
    teams = set()
    for code in [app, *libraries]:
        subprocess.run(
            ['codesign', '--verify', '--all-architectures', '--deep', '--strict', '-R',
             '=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists',
             str(code)], check=True)
        for architecture in sorted(required):
            details = subprocess.run(
                ['codesign', '-d', '--verbose=4', '--architecture', architecture, str(code)],
                check=True, capture_output=True, text=True).stderr
            assert re.search(r'^Authority=Developer ID Application:', details, re.M), f'{code}: Developer ID Application required'
            assert re.search(r'^Timestamp=.+', details, re.M), f'{code}: secure timestamp required'
            team = re.search(r'^TeamIdentifier=([A-Z0-9]{10})$', details, re.M)
            assert team, f'{code}: missing development team'
            teams.add(team.group(1))
            if code == app:
                assert re.search(r'^CodeDirectory .*\(.*runtime.*\)', details, re.M), 'Hardened runtime required'
                entitlements = subprocess.run(
                    ['codesign', '-d', '--architecture', architecture, '--entitlements', '-', str(code)],
                    check=True, capture_output=True).stdout
                values = plistlib.loads(entitlements) if entitlements else {}
                assert not values.get('get-task-allow'), 'Debugging entitlement is not allowed'
                for key in ('get-task-allow', 'cs.allow-jit', 'cs.allow-unsigned-executable-memory',
                            'cs.disable-library-validation', 'cs.allow-dyld-environment-variables'):
                    assert not values.get('com.apple.security.' + key), f'Unexpected runtime exception: {key}'
    assert len(teams) == 1, f'Mixed signing teams: {teams}'
if args.notarized:
    subprocess.run(['xcrun', 'stapler', 'validate', str(app)], check=True)
    subprocess.run(['spctl', '--assess', '--type', 'execute', '--verbose=2', str(app)], check=True)
kind = 'notarized Developer ID' if args.notarized else 'Developer ID' if args.distribution else 'local'
print(f'Mica {info["CFBundleShortVersionString"]}: universal, minimum macOS {minimum}, {kind} signature and dependencies verified.')
PY
