# Validation — Mica 1.2.0 preview · 25 October 2026

## Verified locally

- Apple Silicon M1 MacBook Air, model `MacBookAir10,1`, 8 logical cores, 8 GiB RAM,
  macOS 27.0.1, Swift 6.4 / macOS 27 SDK.
- Universal arm64 + x86_64 release compilation and linking succeeded. `lipo` and
  Mach-O load commands show both architectures and a minimum OS of **12.3**.
  App metadata agrees with the binary. Strict deep signature verification passes.
  No Homebrew or local workspace paths appear in linked library dependencies.
- **37 tests in five suites pass** with normal macOS service access. Coverage
  includes Intel vs Apple Silicon battery capacity units, missing/invalid/zero
  values, 32/64-bit signed current, manufacturing dates, health history persistence,
  hourly deduplication, corrupt-file preservation, CSV safety/privacy, report
  health/version, older preferences, the GlassMeters-to-Mica migration, high core
  counts, SMC decoding, USB/network device parsing, untrusted/disconnected devices,
  restricted iOS diagnostics, sampling/energy/counter behavior, native hit targets
  and the existing sleep-control logic.
- All eight native status-item buttons open their matching popover; repeating
  the active button closes it. The check uses a separate preferences domain.
- Live diagnostics report eight cores, 8 GiB memory, network and disk availability,
  47 named temperature sensors and power telemetry. The local battery reports
  3,655 mAh full-charge capacity, 4,382 mAh design capacity and 605 cycles: **83.41%**
  capacity health. Its IOHID battery-temperature fallback also produces a live reading.
- Native settings show the battery data correctly. A controller's zero time estimate
  is omitted while on AC instead of showing zero battery runtime. Regression tested.
- Saved a real local health snapshot and exercised the native JSON-report and CSV
  save panels. Parsed the exported files to verify version, health, capacity and
  cycles. History/CSV contain a hashed identifier and omit raw serials and names.
- The Devices panel and diagnostics CLI return an explicit no-paired-devices state
  on this machine, with no invented battery health.
- The installed app is `/Applications/Mica.app`. Open at login was enabled through
  its native setting, confirmed in macOS Login Items, and the obsolete GlassMeters
  startup entry was removed. Settings/history survive the update. No persistent
  sleep override was enabled.

## Build-toolchain note

This Apple Silicon CLT distribution omitted x86_64 compatibility archives. The
release links the needed archives from the official Swift 6.2 macOS package,
authenticated by macOS as **Developer ID Installer: Swift Open Source (V9AUD2URP3)**
with trusted Apple notarization and signing timestamp. Its SHA-256 is pinned in
`scripts/prepare-intel-runtime.sh`. The Swift runtime license is included in both
source and app bundle. The package and its expanded toolchain were temporary and
were removed; no alternate toolchain was installed.

The sandboxed AppleScript compile-only check cannot load the normal macOS scripting
services; the full suite passes outside that restriction. Those tests only compile
fixed authorization prompts and do not execute them. The current SwiftPM native
backend emits a deprecation notice, and this CLT emits warnings about its skipped
ARM-only archives during Intel linking; the explicitly supplied Intel archives
resolve the required symbols and the resulting universal bundle verifies.

## Not yet physically verified

- An actual Intel Mac, Monterey or another older macOS installation. Intel linking
  and synthetic Intel fixtures pass; this is not a physical Intel sensor test.
- A real connected iPhone/iPad. The device adapter has fixture and empty-device
  integration coverage, but capacity/health availability varies by iOS release.
- Desktops without batteries, T2-specific firmware, every Intel sensor map,
  PowerPC/32-bit Macs, a real login/reboot, or physically closing a notebook lid.
- GitHub CI execution is recorded separately after publication; its configuration
  runs tests and universal-build verification on Intel and Apple Silicon runners.

This is an independently implemented MIT **preview** with an explicit support
matrix, not a claim that every historical Mac or coconutBattery Plus feature was
physically validated. It is locally ad-hoc signed, not Developer ID notarized.
