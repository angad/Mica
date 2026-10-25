# Contributing

Mica is an independent MIT-licensed implementation. Do not copy code or
assets from coconutBattery, MenuMeters, or another project without a compatible
license and its required attribution. Protocol descriptions and Apple SDK APIs
are the basis for the hardware readers; see [source notes](docs/SOURCES.md).

## Development

Use Swift 6.2 or later and a macOS 26+ SDK. A newer build machine is required even
though the release deployment target is macOS 12. Build and test:

```sh
./scripts/build.sh --universal
./scripts/test.sh
./dist/Mica.app/Contents/MacOS/Mica --diagnose
```

Keep hardware calls off the main thread. Represent missing readings explicitly;
do not substitute a healthy-looking zero. Normalize units at the data boundary.
Changes to telemetry need fixtures for Intel and Apple Silicon data, missing and
malformed values, and at least one relevant regression test. Preserve old saved
preferences when adding fields.

## Hardware reports

Please include the Mac model identifier, CPU architecture, macOS version, app
version, the affected reading, and whether the machine is on battery or AC.
State whether you used physical hardware, Rosetta, a virtual machine, or a fixture.
Never describe an Intel cross-build as a physical Intel test.

Review diagnostics before attaching them: reports contain local hardware metrics.
Do not attach raw IORegistry dumps, pairing records, serial numbers, UDIDs, or
unredacted personal device names. Create synthetic fixtures with the same field
names and units instead.

## Release validation

Run the unit suite, compile both architectures, verify code signatures and
deployment targets, and exercise settings and popovers on the target machine.
Update `VALIDATION.md` and the compatibility table with exact evidence and limits.
Reboot/login and older physical hardware remain separate manual checks. Never
enable the persistent lid-sleep override as part of automated tests.

Public Developer ID releases use the staged [notarization workflow](docs/NOTARIZATION.md).
Run its release-boundary tests with `python3 -m unittest discover -s Tests/ReleaseTests`.
Local CI signatures are deliberately rejected by the distribution verifier.
