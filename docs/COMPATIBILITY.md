# Compatibility

The 1.2 release target is **macOS 12.3 Monterey or later, arm64 and x86_64**.
This is the oldest deployment target supported by the macOS 27 SDK used here.
Many older Intel Macs can run Monterey, including models supported through
third-party OS patches, but a successful build is not proof of every model's sensors.

| Platform | Core meters | Temperatures | Battery health | Whole-system power |
| --- | --- | --- | --- | --- |
| Apple Silicon notebook | Mach, sysctl, route counters, IOKit | Optional runtime IOHID interface | AppleSmartBattery + public IOPS fallback | Battery telemetry; discharge electrical fallback; optional SMC PSTR |
| Apple Silicon desktop | Same | Optional runtime IOHID interface | No internal battery is expected | Optional SMC PSTR; unavailable when firmware withholds it |
| Intel notebook | Same | Read-only AppleSMC enumeration plus common-key fallback | Intel mAh normalization + public IOPS fallback | Optional SMC PSTR or discharge electrical fallback |
| Intel desktop / Mac Pro | Same; up to 256 logical cores | Read-only AppleSMC when available | No internal battery is expected | Optional SMC PSTR |
| Virtual machine | Whatever the guest exposes | Usually unavailable | Usually unavailable | Usually unavailable |
| macOS 12.2 and earlier | Not supported by the release binary | — | — | — |
| PowerPC or 32-bit Intel | Not supported by Swift runtime / binary architecture | — | — | — |

## UI and login startup

- macOS 26+: Liquid Glass where available.
- macOS 12.3–25: native material surfaces and the same settings and meters.
- macOS 13+: `SMAppService` login registration.
- macOS 12.3: per-user `RunAtLoad` LaunchAgent. No privileged helper or keep-alive loop.
- UI screenshot automation requires macOS 14.4+, independently of app runtime support.

## Hardware fallbacks and boundaries

Thermal services and SMC keys are undocumented firmware interfaces. Missing
symbols, denied access, missing keys and invalid readings produce unavailable
values instead of preventing launch. SMC access uses metadata, index and read
commands only; there is no write or fan-control command. Enumeration is bounded
and sensor identities are cached while readings stay live.

Core CPU/memory/network/storage meters use architecture-independent macOS APIs.
Network data prefers 64-bit `NET_RT_IFLIST2` counters. CPU counters handle tick
rollover. Energy excludes missing readings, long gaps and sleep. Up to 256 logical
cores are sampled; large machines group the menu-bar bars into at most 32 groups.
The CPU details still report the full logical core count.

Intel `CurrentCapacity` and `MaxCapacity` can be mAh; Apple Silicon can expose
percentages under those same keys. Health uses raw/full-charge and design mAh
only. Health is not inferred when those values are absent. Signed current handles
both 32-bit and 64-bit wrapped integers. Controller temperatures use tenths of
Kelvin; unrelated iOS GasGauge temperature fields are not guessed into Celsius.

## iPhone and iPad

Install the optional `libimobiledevice` tools yourself and pair/trust the device
with Finder. USB is the default; existing Wi-Fi pairing is opt-in. Tools are
discovered in standard Homebrew, Intel Homebrew, MacPorts and system locations.
They are not bundled in the MIT source or app release.

The adapter reads the device's identity, the public battery domain, GasGauge
diagnostics and, when needed, AppleSmartBattery registry data. Some iOS releases
withhold full capacity, design capacity or cycle count. Charge and charging state
can still be shown without inventing a health percentage. A locked, disconnected,
unpaired or timed-out device has an explicit error state. Each subprocess has a
five-second deadline; scanning runs off the main thread and handles at most eight
devices per refresh. It never sends sleep, restart, shutdown, pairing or write commands.

Physical Intel, older macOS and real iPhone/iPad checks must be recorded separately
in `VALIDATION.md`; fixture coverage is not a substitute for them.
