# Resource usage

Mica's menu bar shows the Mac's CPU and memory. This note measures the Mica
process itself, separately from those whole-system readings.

## Measured sample — 25 October 2026

| Setting | Value |
| --- | --- |
| App | Mica 1.2.0, installed universal release, running natively |
| Mac | M1 MacBook Air (`MacBookAir10,1`), 8 logical cores, 8 GB RAM |
| macOS | 27.0.1 |
| Mode | Menu bar active; settings and popovers closed |
| Refresh | 1 second |
| Meters | CPU per-core bars, memory, network, disk, temperature and power |
| Sensors | 47 available temperature sensors |
| Optional features | iOS polling and hourly battery history off; stay-awake controls off |
| Sample | 60.01 seconds, 61 observations |
| Mean CPU | 3.78% of one core |
| Median resident memory | 38.64 MiB RSS |
| Peak resident memory | 39.42 MiB RSS |

Other apps were running, and the system was under memory pressure. This is one
observed sample, not a performance guarantee or an idle-machine benchmark. Sensor
availability, refresh rate, visible windows, OS version and workload change usage.

CPU is the increase in the process's cumulative user + system CPU time divided
by elapsed wall time, multiplied by 100. A fully occupied core is 100%; multiple
busy threads can exceed 100%. It is not normalized across all eight cores.

RSS is `ps` resident memory, converted from KiB to MiB. It includes resident shared
pages and omits compressed/swapped-out pages; it is not total allocated memory,
private memory, or Activity Monitor's memory-footprint column. Compare like for like.

Raw evidence: [summary JSON](performance/m1-2026-10-25.json) ·
[individual samples CSV](performance/m1-2026-10-25.csv).

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
transmit results, or run inside the installed Mica app. Record your hardware,
refresh interval and enabled features alongside the generated JSON and CSV.
