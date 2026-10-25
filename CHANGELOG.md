# Changelog

## 1.3.0 — 2026-10-25

- Reduce background temperature polling by caching sensor discovery and reading
  the selected sensor each tick; refresh other sensors every 30 seconds or while
  a temperature view is open. Release closed settings and popover views.
- Show the five largest processes by CPU and physical memory footprint in CPU
  and Memory details. The shared two-second sampler runs only with a visible list.
- Add opt-in local alerts for CPU, memory pressure, home-volume free space, Mac
  battery charge and temperature, with thresholds, duration, cooldown and bounded
  in-memory history.
- Add timed idle-sleep prevention by duration or end time, context-menu presets,
  deadline checks after wake and an optional battery cutoff. Sessions release
  their assertion on expiry or quit; persistent lid settings remain separate.
- Remove periodic lid-setting polling; refresh it when controls open or the Mac wakes.

## 1.2.0 — 2026-10-25

First MIT open-source release under the name **Mica**. Existing GlassMeters
preferences migrate without changing the original settings domain.

- Mac battery capacity, health, cycle count, electrical readings and available
  controller details; local health snapshots, history charts and CSV/JSON export.
- Optional paired iPhone/iPad diagnostics over USB and existing Wi-Fi pairing,
  with explicit unavailable/locked/disconnected states.
- Universal arm64/x86_64 distribution targeting macOS 12.3 and later. Native
  material fallback on older macOS, with Liquid Glass on macOS 26+.
- Read-only Intel SMC sensor discovery, architecture-independent CPU/memory/disk
  monitoring, 64-bit network counters and large-core-count layouts.
- Battery unit normalization, signed-current handling, safe history writes,
  privacy-preserving device IDs, preference migration and regression tests.
- Reproducible build, test, packaging and verification scripts, Intel/Apple Silicon
  CI configuration, compatibility boundaries, license and contributor guidance.

Hardware validation remains narrower than the build target: see `VALIDATION.md`.
