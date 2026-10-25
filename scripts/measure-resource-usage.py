#!/usr/bin/env python3
"""Manually sample one running process; this is not part of the installed app."""
import argparse
import csv
from datetime import datetime, timezone
import json
from pathlib import Path
import platform
import statistics
import subprocess
import time


def cpu_seconds(value):
    days, clock = value.split("-", 1) if "-" in value else ("0", value)
    result = 0.0
    for component in clock.split(":"):
        result = result * 60 + float(component)
    return int(days) * 86400 + result


def sample(pid):
    fields = subprocess.check_output(
        ["ps", "-p", str(pid), "-o", "time=", "-o", "rss="], text=True).split()
    if len(fields) != 2:
        raise RuntimeError("The requested process is no longer running")
    return cpu_seconds(fields[0]), int(fields[1]) / 1024


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", required=True, type=int)
    parser.add_argument("--duration", type=int, default=60)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.duration < 1:
        parser.error("--duration must be positive")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    cpu_start, rss = sample(args.pid)
    start = time.monotonic()
    readings = [{"elapsed_seconds": 0.0, "cpu_seconds": cpu_start, "rss_mib": rss}]
    while time.monotonic() - start < args.duration:
        time.sleep(min(1, max(0, args.duration - (time.monotonic() - start))))
        cpu, rss = sample(args.pid)
        readings.append({"elapsed_seconds": time.monotonic() - start, "cpu_seconds": cpu, "rss_mib": rss})
    elapsed = readings[-1]["elapsed_seconds"]
    summary = {
        "measured_at_utc": datetime.now(timezone.utc).isoformat(),
        "model": subprocess.check_output(["sysctl", "-n", "hw.model"], text=True).strip(),
        "architecture": platform.machine(),
        "macos": subprocess.check_output(["sw_vers", "-productVersion"], text=True).strip(),
        "elapsed_seconds": elapsed,
        "samples": len(readings),
        "cpu_percent_one_core": 100 * (readings[-1]["cpu_seconds"] - cpu_start) / elapsed,
        "rss_mib_median": statistics.median(row["rss_mib"] for row in readings),
        "rss_mib_peak": max(row["rss_mib"] for row in readings),
    }
    args.output.with_suffix(".json").write_text(json.dumps(summary, indent=2) + "\n")
    with args.output.with_suffix(".csv").open("w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=list(readings[0]))
        writer.writeheader()
        writer.writerows(readings)
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
