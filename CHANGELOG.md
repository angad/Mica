# Changelog

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
