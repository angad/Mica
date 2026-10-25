# Developer guide

Maintained by [Angad Singh](https://github.com/angad). Mica is an independent
MIT-licensed native macOS app. This guide contains build, hardware, diagnostics
and release details; the [README](README.md) is the product overview.

## Build and run

Build tools: Swift 6.2+ and a macOS 26+ SDK (Xcode or Command Line Tools).
Building requires a newer Mac/OS than running the finished app.

```sh
./scripts/build.sh --universal
./scripts/test.sh
./scripts/verify-release.sh
open dist/Mica.app
```

Omit `--universal` for a host-only development build. If an Apple Silicon-only
Command Line Tools distribution lacks Intel compatibility archives, run
`./scripts/prepare-intel-runtime.sh` first. It temporarily downloads the official
1.65 GiB Swift 6.2 package, checks its pinned SHA-256 and Apple notarization,
extracts the archives, and deletes the temporary download without installing a
toolchain. A full Xcode distribution with Intel archives does not need this step.
Set `MICA_INTEL_RUNTIME_DIR` to use an existing compatible archive directory.

The release script creates an
arm64 + x86_64 bundle, includes required back-deployment libraries, and signs it
locally. It is not Developer ID signed or notarized for public binary distribution.

Copy `Mica.app` to Applications before enabling **General → Open at login**.
Click a meter for details; right-click the group for settings, pause or quit. Hold
Command and drag the group to reposition it. Reopen the app to show settings.
The optional Battery meter is off by default to preserve existing layouts; its
health panel is always available in Settings → Battery. Existing GlassMeters preferences migrate automatically.

## iPhone and iPad setup

Install the optional tools separately:

```sh
brew install libimobiledevice
```

Connect and unlock the device, then trust/pair with the Mac using Finder. In
**Settings → Devices**, turn on monitoring or choose **Refresh devices** for a
one-time read. Existing Wi-Fi pairing is a separate opt-in setting. The app never
pairs, restarts, sleeps, shuts down, or writes to a device. The tools are not bundled.
Some iOS versions withhold cycle count and full/design capacity; the UI says so.

## Battery history and privacy

Save a health snapshot manually or enable hourly saving. History is stored locally
under `~/Library/Application Support/Mica/battery-history.json`, bounded to
10,000 records. Device identifiers are hashed, and personal device names are not
stored in history or its CSV export. A manually exported current JSON report does
include the display name; review it before sharing. Health estimates can fluctuate
and may exceed 100% on a new battery. Missing capacity does not become 100% health.

Manufacture dates are decoded only from valid battery-controller date fields;
modern randomized Apple serial numbers are not decoded into guessed dates.

## Power and sleep controls

Charger input uses `PowerTelemetryData.SystemPowerIn`; system consumption uses
`SystemLoad`, a supported SMC `PSTR` reading, or battery voltage × signed discharge
current. These are hardware estimates, not an external wall-plug measurement.
`AdapterDetails.Watts` is rated capacity and never substituted for live input.

**Stay awake** holds an idle-sleep assertion while the app runs. It does not prevent
explicit sleep or lid-close sleep. **No sleep when lid closed** is a separate,
opt-in global `pmset disablesleep` setting requiring the native macOS administrator
prompt. It persists after quitting until switched off. Turn it off before carrying
a notebook in a bag. Neither control is enabled automatically.

## Diagnostics

```sh
./dist/Mica.app/Contents/MacOS/Mica --diagnose
./dist/Mica.app/Contents/MacOS/Mica --diagnose-devices
./dist/Mica.app/Contents/MacOS/Mica --check-clicks
```

Diagnostics only print local samples. Run outside restrictive shell sandboxes to
access normal macOS services. Review data before attaching a report to an issue.
`--check-clicks` uses a separate settings domain and exercises native status-item
hit targets; it does not change the persistent sleep setting.

## Open-source development

See [contributing](CONTRIBUTING.md), [security/privacy](SECURITY.md), and
[interface references](docs/SOURCES.md). MenuMeters and coconutBattery are feature
references, not bundled dependencies or copied implementations. This release does
not claim every coconutBattery Plus feature: SSD lifetime analysis, notifications,
print templates and online history comparisons are outside its scope.

CI builds both binary architectures and runs the unit suite. Physical tests on
older Intel Macs, older macOS releases and connected iOS devices are needed before
expanding validated compatibility claims. To prepare distributable source and app archives:

```sh
./scripts/package-release.sh
```

[MIT License](LICENSE)

## Homebrew distribution

The cask lives in [angad/homebrew-tap](https://github.com/angad/homebrew-tap/blob/main/Casks/mica.rb).
Update its version and SHA-256 after publishing the universal ZIP. Keep the
unsigned-preview caveat until Developer ID signing and notarization are complete.
Homebrew quarantine is preserved. See [Homebrew distribution details](docs/HOMEBREW.md).

## Resource measurements and screenshots

The [performance note](docs/PERFORMANCE.md) includes a reproducible manual sampler
and raw measurements. It is a developer tool; the installed app does not run it.
The README screenshots were captured from the real app on macOS 27.0.1 using the
existing app-only window export. They show real readings, not simulated device data.
