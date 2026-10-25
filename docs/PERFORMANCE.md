# Resource usage

Mica's menu bar shows the Mac's CPU and memory. This note measures the Mica
process itself, separately from those whole-system readings.

## Measured samples — 25 October 2026

| Resource | Mica 1.2.0 | Mica 1.3.0 |
| --- | --- | --- |
| Mean CPU, one core = 100% | 3.78% | 0.53% |
| Median resident memory, RSS | 38.64 MiB | 34.55 MiB |
| Peak resident memory during sample, RSS | 39.42 MiB | 44.78 MiB |
| Duration / observations | 60.01 s / 61 | 60.01 s / 61 |

The observed CPU reduction is 85.9%. These are separate local samples,
not a controlled experiment or a performance guarantee. Other apps were running,
and the system was under memory pressure. RSS can change as macOS compresses or
pages memory; the lower median does not establish an equivalent reduction in
allocations. The 1.3.0 sample has a higher RSS peak.

| Setting | Value |
| --- | --- |
| Mac | M1 MacBook Air (`MacBookAir10,1`), 8 logical cores, 8 GB RAM |
| macOS | 27.0.1 |
| App | Installed universal release, running natively on arm64 |
| Mode | Menu bar active; settings and popovers closed after visiting settings |
| Refresh | 1 second |
| Meters | CPU per-core bars, memory, network, disk, temperature and power |
| Sensors | 47 available temperature sensors; automatic selected sensor |
| Optional features | iOS polling, hourly battery history and stay-awake controls off |
| 1.3.0 alerts | Notification permission allowed; master and individual rules off |
| 1.3.0 process lists | CPU view visited, then closed; polling stops with its views |

No local builds or unit tests ran during the final 1.3.0 measurement. Earlier
profiling and an intermediate measurement were used to select the changes;
the table above uses the finished app with all three new features installed.

## Changes

A five-second sampling profile of 1.2.0 showed repeated IOHID temperature-event
reads as the largest active sampling-thread cost. Closed SwiftUI settings views
also retained their observations and continued updating.

1.3.0 caches IOHID service discovery for up to 60 seconds. The selected temperature
sensor updates at the configured interval; the remaining sensors refresh every
30 seconds in the background. A visible temperature panel requests detailed live
reads. Intel SMC reads follow the same selected-sensor/full-list split. Closed
settings and popover hosting views are released, and unchanged meter geometry
does not trigger another layout.

The process sampler runs every two seconds only while a CPU or memory process
list is visible. Alerts evaluate existing snapshots; home-volume free space is
read at most once every 30 seconds only when that alert is enabled. Timed sessions
use one nonrepeating deadline timer. Lid-setting polling was replaced with reads
when the controls open or the Mac wakes.

## Definitions and raw measurements

CPU is the increase in cumulative user + system CPU time divided by elapsed wall
time, multiplied by 100. A fully occupied core is 100%; multiple busy threads can
exceed 100%. It is not normalized across all eight cores.

RSS is `ps` resident memory, converted from KiB to MiB. It includes resident shared
pages and omits compressed/swapped-out pages; it is not total allocated memory,
private memory, or Activity Monitor's physical-footprint column. Compare like for like.

- 1.2.0: [summary JSON](performance/m1-2026-10-25.json) · [samples CSV](performance/m1-2026-10-25.csv).
- 1.3.0: [summary JSON](performance/m1-1.3.0-2026-10-25.json) · [samples CSV](performance/m1-1.3.0-2026-10-25.csv).

## Reproduce

Run Mica, close its settings window/popovers, and ensure only one Mica process is
running. From a normal terminal with macOS process access:

```sh
python3 scripts/measure-resource-usage.py \
  --pid "$(pgrep -x Mica)" \
  --duration 60 \
  --output .build/resource-usage
```

The sampler reads only the specified process. It does not inspect other apps,
transmit results, or run inside the installed app. Record hardware, refresh
interval and enabled features alongside the generated JSON and CSV.
