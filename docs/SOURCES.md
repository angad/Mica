# Interface references and implementation notes

Mica is independently implemented and released under MIT. These references
describe APIs, protocols, product capabilities and compatibility lessons; their
application source and artwork are not incorporated into Mica.

- [MenuMeters](https://github.com/yujitach/MenuMeters), GPL-2.0: the familiar compact
  meter layout and lessons from its Intel/Apple Silicon transition. Its temperature
  reader selects SMC for Intel and IOHID for Apple Silicon. Mica independently
  probes optional interfaces and uses a read-only SMC wire adapter. Its native
  status items avoid loading code into SystemUIServer or System Preferences.
- [MenuMeters release history](https://github.com/yujitach/MenuMeters/blob/main/releases.html):
  architecture changes, status-item lifecycle, sensor choice, memory accounting
  and network-counter regressions motivate explicit compatibility fixtures.
- [coconutBattery](https://www.coconut-flavour.com/coconutbattery/): feature reference
  for Mac and paired iOS battery capacity, cycles and saved health history.
  Mica does not reuse its proprietary implementation, screenshots, database
  or branding. SSD lifetime analysis, online history comparison, print templates
  and notifications are not claimed as feature parity in 1.2.
- [Apple IOPS keys](https://github.com/apple-oss-distributions/IOKitUser/blob/main/ps.subproj/IOPSKeys.h):
  public battery charge, charging state, power-source state and time estimates.
- [Apple IOHIDFamily](https://github.com/apple-oss-distributions/IOHIDFamily):
  temperature-event interface definitions. Symbols are resolved at runtime.
- [Apple XNU](https://github.com/apple-oss-distributions/xnu): Mach CPU/VM counters
  and the routing interface's 64-bit network statistics.
- [libimobiledevice diagnostics tool](https://github.com/libimobiledevice/libimobiledevice/blob/master/tools/idevicediagnostics.c),
  LGPL-2.1-or-later: optional, separately installed command-line interface.
  Mica invokes its unmodified executable; no library or source is bundled.

The SMC adapter describes the driver's fixed-size wire packet through byte offsets
and supports only key metadata (9), key index (8), and key read (5). Fixed-point and
float decoding is unit-tested. Protocol facts are used for interoperability;
there is no copied SMC application implementation or write-capable backend.
