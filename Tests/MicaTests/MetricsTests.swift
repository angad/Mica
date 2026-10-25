import Foundation
import Hardware
import Testing

@testable import Mica

@Suite struct MetricsTests {
  @Test func temperatureSelectionPrioritiesMatchDisplayedReadings() {
    #expect(gm_sensor_rank("SOC MTR Temp Sensor0", "Automatic") == 0)
    #expect(gm_sensor_rank("CPU die (TC0D)", "Automatic") == 1)
    #expect(gm_sensor_rank("CPU proximity", "Automatic") == 2)
    #expect(gm_sensor_rank("GPU die", "Automatic") == -1)
    #expect(gm_sensor_rank("pACC MTR Temp Sensor0", "CPU average") == 0)
    #expect(gm_sensor_rank("eACC MTR Temp Sensor0", "CPU average") == 0)
    #expect(gm_sensor_rank("GPU die", "CPU average") == -1)
    #expect(gm_sensor_rank("Battery (TB0T)", "Battery (TB0T)") == 0)
    #expect(gm_sensor_rank("CPU die", "Missing sensor") == -1)
  }
  @Test func ratesAndCounterResets() {
    #expect(counterRate(2500, 500, elapsed: 2) == 1000)
    #expect(counterRate(10, 1000, elapsed: 1) == 0)
    #expect(counterRate(500, 0, elapsed: 0) == 0)
    #expect(tickDelta(3, UInt64(UInt32.max) - 2) == 6)
  }
  @Test func powerIntegrationAndSleepGaps() {
    #expect(
      abs(energyIncrement(previous: 10, current: 30, seconds: 3, maxGap: 10) - 1.0 / 60) < 0.000001)
    #expect(energyIncrement(previous: 10, current: 30, seconds: 3600, maxGap: 10) == 0)
    #expect(energyIncrement(previous: nil, current: 30, seconds: 1, maxGap: 10) == 0)
    #expect(energyIncrement(previous: 10, current: .nan, seconds: 1, maxGap: 10) == 0)
  }
  @Test func formatting() {
    #expect(rate(136200) == "136.2KB/s")
    #expect(rate(15_800_000) == "15.8MB/s")
    #expect(rate(125000, bits: true) == "1.0Mb/s")
    #expect(temperatureText(0, fahrenheit: true) == "32.0°F")
    #expect(watts(nil) == "— W")
  }
  @Test func defaultLayoutAndSettingsRoundTrip() throws {
    let original = Preferences()
    #expect(
      Meter.allCases.map(\.rawValue) == [
        "memory", "network", "disk", "temperature", "cpu", "input", "consumption", "battery",
      ])
    #expect(original.enabled.count == 7)
    #expect(
      try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(original)) == original)
  }
  @Test func disabledMetersRemainRecoverable() {
    var p = Preferences()
    p.enabled = []
    #expect(MeterPainter.regions(Snapshot(), p).isEmpty)
    #expect(MeterPainter.image(Snapshot(), p, dark: false).size.width > 0)
  }
  @Test func telemetryAndSleepGaps() {
    let defaults = UserDefaults(suiteName: "sg.angad.Mica.unit-tests")!
    let settings = Settings(defaults: defaults)
    settings.reset()
    let monitor = Monitor(settings: settings, start: false)
    var raw = GMSample()
    raw.system_watts = 12
    raw.charger_watts = 18
    raw.adapter_watts = 90
    monitor.accept(raw, time: 100)
    #expect(monitor.history.isEmpty)
    monitor.accept(raw, time: 103)
    #expect(monitor.snapshot.systemWatts == 12)
    #expect(monitor.snapshot.inputWatts == 18)
    #expect(monitor.snapshot.adapterWatts == 90)
    #expect(abs(monitor.snapshot.sessionWh - 0.01) < 0.000001)
    monitor.accept(raw, time: 400)
    #expect(monitor.history.count == 1)
    #expect(abs(monitor.snapshot.sessionWh - 0.01) < 0.000001)
    monitor.resetEnergy()
    #expect(monitor.snapshot.sessionWh == 0)
    defaults.removePersistentDomain(forName: "sg.angad.Mica.unit-tests")
  }
  @Test func cpuAlertsRequireTwoValidComparableSamples() {
    let domain = "sg.angad.Mica.cpu-validity-tests"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let monitor = Monitor(settings: Settings(defaults: defaults), start: false)
    var raw = GMSample()
    raw.core_count = 1
    monitor.accept(raw, time: 100)
    raw.cpu_valid = 1
    monitor.accept(raw, time: 101)
    #expect(!monitor.snapshot.cpuAvailable)
    monitor.accept(raw, time: 102)
    #expect(monitor.snapshot.cpuAvailable)
    raw.core_count = 2
    monitor.accept(raw, time: 103)
    #expect(!monitor.snapshot.cpuAvailable)
    monitor.accept(raw, time: 400)
    #expect(!monitor.snapshot.cpuAvailable)
  }
}
