<p align="center">
  <img src="docs/screenshots/icon.png" width="88" alt="Mica app icon">
</p>

<h1 align="center">Mica</h1>
<p align="center"><strong>Your Mac, at a glance.</strong></p>
<p align="center">Live system stats, battery health and stay-awake controls in one native menu bar app.</p>
<p align="center"><a href="#install">Install with Homebrew</a> · <a href="#screenshots">Screenshots</a> · <a href="#privacy">Privacy</a> · <a href="DEVELOPMENT.md">Developer guide</a></p>

<p align="center"><img src="docs/screenshots/menubar.png" alt="Mica’s live menu bar meters"></p>

Mica brings together the everyday features you know from **MenuMeters**,
**coconutBattery**, and **Caffeine / Amphetamine**: see what your Mac is doing,
understand its battery, and keep it awake when you need it.

**Free. Open source. No account. No data collection.**

## Install

```sh
brew install --cask angad/tap/mica
```

Or [download the latest preview](https://github.com/angad/Mica/releases/tag/v1.2.0)
and drag Mica to Applications. Built for **Apple Silicon and Intel**, on
**macOS 12.3 Monterey or later**.

The current preview is ad-hoc signed and **not yet notarized**. If macOS blocks
its first launch, review [Apple’s instructions for opening an app you trust](https://support.apple.com/en-us/102445).
Homebrew preserves macOS security checks. [Installation details](docs/HOMEBREW.md).

## Know what’s happening

- **CPU:** live total load, per-core bars, user/system breakdown and recent history.
- **Memory:** used and available RAM, memory pressure, wired, active and compressed
  memory, plus swap usage. Choose stacked bars or a percentage.
- **Network and storage:** upload/download rates, interface selection and disk
  read/write activity.
- **Temperature and power:** available hardware sensors, charger input, system
  power draw and energy over the current session.

Click a meter for the details. Pick the meters, colors and update interval that
suit your menu bar. Native dark and light appearances, with Liquid Glass on macOS 26+.

## Understand your battery

See capacity health, full-charge versus design capacity, cycle count, charge,
temperature, voltage and current. Save health snapshots, follow capacity over time,
and export CSV history or a JSON report. History stays on your Mac.

**iPhone and iPad, too:** optional read-only diagnostics for devices paired with
your Mac. Install `libimobiledevice` separately and enable Devices in settings.
Available battery details depend on the device and iOS version.

## Stay awake when it matters

Keep your Mac awake during a download, presentation or long-running task with one
switch. The idle-sleep assertion is released when Mica quits.

A separate, opt-in **No sleep when lid closed** control is available on notebooks.
It needs macOS administrator approval and stays enabled until you turn it off.
Turn it off before carrying your Mac in a bag.

## Screenshots

Real app windows and live readings on an M1 MacBook Air.

<table>
  <tr>
    <td width="50%"><img src="docs/screenshots/cpu.png" alt="CPU load, history and per-core display settings"><br><strong>CPU at a glance</strong></td>
    <td width="50%"><img src="docs/screenshots/memory.png" alt="Memory pressure, RAM categories and swap usage"><br><strong>Memory, explained</strong></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/battery.png" alt="Mac battery health, full/design capacity and cycle count"><br><strong>Battery health and cycles</strong></td>
    <td><img src="docs/screenshots/stay-awake.png" alt="Stay-awake controls and menu bar customization"><br><strong>Stay awake and make it yours</strong></td>
  </tr>
</table>

## Privacy

**No data collection or tracking.** Mica reads hardware stats locally and does
not send them to us or to an analytics service. There are no tracking SDKs, ads,
accounts, cloud uploads or Mica servers.

Battery history is saved locally when you choose to save a snapshot or enable
hourly history. You control report exports. Optional Wi-Fi device reads use your
existing local pairing. [Privacy details](SECURITY.md).

## Mica’s own CPU and memory use

Measured with the settings window closed and the menu bar updating every second:

| Resource | M1 MacBook Air sample |
| --- | --- |
| CPU | **3.8% of one core**, average |
| Resident memory (RSS) | **38.6 MiB**, median |
| Peak resident memory (RSS) | **39.4 MiB** |

One 60-second sample on an 8 GB M1 MacBook Air running macOS 27.0.1, Mica 1.2.0.
Other apps were running. RSS counts resident pages; it is not total allocated
memory. Usage varies with hardware, sensors and settings.
[Method and raw measurements](docs/PERFORMANCE.md).

## Open source, built for the Mac

Mica is independently built and [MIT licensed](LICENSE). It covers the system
monitoring, battery insights and stay-awake essentials above; it does not claim
complete feature parity with the apps that inspired it. Sensor availability
varies by Mac and firmware. [Compatibility](docs/COMPATIBILITY.md) ·
[Validation](VALIDATION.md).

Built by [Angad Singh](https://github.com/angad).
[Developer guide](DEVELOPMENT.md) · [Contributing](CONTRIBUTING.md) ·
[Report an issue](https://github.com/angad/Mica/issues).
