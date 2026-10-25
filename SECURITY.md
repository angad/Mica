# Security and privacy

Mica samples local hardware and, while a process list is visible, local process usage. It has no telemetry, account, update-server
connection, cloud history, root helper, kernel extension, or device-write path.
The optional iPhone/iPad adapter invokes installed libimobiledevice tools with
fixed, read-only commands. It does not pair devices or change their trust state.
The opt-in Wi-Fi option connects only through existing local device pairing.

Battery history is local, opt-in, bounded to 10,000 records, and written atomically
with owner-only file permissions. Identifiers are hashed. History omits raw
serial numbers, UDIDs and personal device names. CSV exports use those same fields.
An explicitly exported current report includes the device's display name; inspect
it before sharing. The app does not infer manufacturing dates from modern serials.

Stay awake uses an in-process power assertion. The separate lid-sleep control
requests macOS administrator authorization for one of two fixed `pmset` commands.
It changes a persistent system setting and remains opt-in. Quitting releases
idle-sleep assertions but does not secretly change the persistent setting.

Report vulnerabilities privately to the repository maintainer through GitHub's
private vulnerability reporting feature when available. Do not post secrets or
device pairing records in public issues.

Process lists read names, PIDs, start times, CPU counters and physical footprint.
They do not read arguments, environment variables or window titles, and are not
saved or uploaded. The explicit process diagnostic command prints its results
locally; review the output before sharing it. Alerts are evaluated locally and
use macOS local notifications. The latest 20 events remain in memory only, until
cleared or the app quits. No remote notification service is used.
