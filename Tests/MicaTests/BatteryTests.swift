import Foundation
import Hardware
import Testing

@testable import Mica

@Suite struct BatteryTests {
  @Test func batteryTimeEstimatesDoNotShowZeroRemainingWhileOnAC() {
    var reading = BatteryReading(id: "test", name: "Test")
    reading.externalPower = true
    reading.charging = false
    reading.timeToEmptyMinutes = 60
    #expect(reading.timeEstimate == nil)
    reading.externalPower = false
    #expect(reading.timeEstimate?.minutes == 60)
    reading.externalPower = true
    reading.charging = true
    reading.timeToFullMinutes = 30
    #expect(reading.timeEstimate?.minutes == 30)
    reading.timeToFullMinutes = 0
    #expect(reading.timeEstimate == nil)
    #expect(BatteryParser.minutes(["AvgTimeToEmpty": 0], "AvgTimeToEmpty") == nil)
  }
  @Test func currentReportsIncludeComputedHealthAndVersion() throws {
    var reading = BatteryReading(id: "test", name: "Test")
    reading.fullChargeCapacityMAh = 4000
    reading.designCapacityMAh = 5000
    let report = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(BatteryReport(reading)))
        as? [String: Any])
    #expect(report["healthPercent"] as? Double == 80)
    #expect(report["appVersion"] as? String == "1.2.0")
  }
  @Test func renamedAppMigratesLegacyPreferencesWithoutChangingTheOriginal() throws {
    let identifier = UUID().uuidString
    let oldDomain = "sg.angad.Mica.test-old-\(identifier)"
    let newDomain = "sg.angad.Mica.test-new-\(identifier)"
    let old = UserDefaults(suiteName: oldDomain)!
    let new = UserDefaults(suiteName: newDomain)!
    defer {
      old.removePersistentDomain(forName: oldDomain)
      new.removePersistentDomain(forName: newDomain)
    }
    var preferences = Preferences()
    preferences.compact = true
    preferences.interval = 2
    let original = try JSONEncoder().encode(preferences)
    old.set(original, forKey: "preferences.v1")
    let migrated = Settings(defaults: new, legacyDefaults: old)
    #expect(migrated.value.compact)
    #expect(migrated.value.interval == 2)
    #expect(new.data(forKey: "preferences.v1") != nil)
    #expect(old.data(forKey: "preferences.v1") == original)
    migrated.value.interval = 5
    #expect(old.data(forKey: "preferences.v1") == original)
  }
  @Test func appleSiliconPercentageCapacityDoesNotBecomeMAh() throws {
    let r = BatteryParser.registry([
      "CurrentCapacity": 80, "MaxCapacity": 100, "CycleCount": 605,
      "BatteryData": [
        "DesignCapacity": 4382, "FullChargeCapacity": 3655,
        "NominalChargeCapacity": 3785, "RemainingCapacity": 2924,
      ],
    ])
    #expect(r.chargePercent == 80)
    #expect(r.fullChargeCapacityMAh == 3655)
    #expect(r.currentCapacityMAh == 2924)
    #expect(abs(try #require(r.healthPercent) - 83.4094) < 0.001)
    #expect(r.cycleCount == 605)
  }
  @Test func intelMAhCapacityIsNormalizedToPercentage() throws {
    let r = BatteryParser.registry([
      "CurrentCapacity": 2000, "MaxCapacity": 4000,
      "DesignCapacity": 5000, "CycleCount": 123, "Temperature": 2981, "Voltage": 12000,
      "Amperage": NSNumber(value: UInt32.max - 999), "ExternalConnected": false,
    ])
    #expect(r.chargePercent == 50)
    #expect(r.healthPercent == 80)
    #expect(r.currentCapacityMAh == 2000)
    #expect(r.currentMA == -1000)
    #expect(r.batteryWatts == -12)
    #expect(abs(try #require(r.temperatureCelsius) - 24.95) < 0.001)
  }
  @Test func absentAndInvalidFieldsNeverLookLikeHealthyZeroCycleBattery() {
    let missing = BatteryParser.registry([:])
    #expect(missing.healthPercent == nil)
    #expect(missing.cycleCount == nil)
    #expect(missing.chargePercent == nil)
    #expect(missing.charging == nil)
    let invalid = BatteryParser.registry([
      "CurrentCapacity": 101, "MaxCapacity": 100,
      "DesignCapacity": 0, "CycleCount": -1, "Temperature": 65535, "Voltage": 0,
      "Amperage": UInt64.max / 2, "AvgTimeToEmpty": 65535,
    ])
    #expect(invalid.chargePercent == nil)
    #expect(invalid.healthPercent == nil)
    #expect(invalid.cycleCount == nil)
    #expect(invalid.temperatureCelsius == nil)
    #expect(invalid.currentMA == nil)
    #expect(invalid.timeToEmptyMinutes == nil)
    #expect(BatteryParser.number(["Cycles": true], ["Cycles"]) == nil)
  }
  @Test func zeroChargeZeroCyclesAndGreaterThanDesignHealthAreValid() {
    let r = BatteryParser.registry([
      "CurrentCapacity": 0, "MaxCapacity": 100,
      "CycleCount": 0, "BatteryData": ["FullChargeCapacity": 5100, "DesignCapacity": 5000],
    ])
    #expect(r.chargePercent == 0)
    #expect(r.cycleCount == 0)
    #expect(r.healthPercent == 102)
    #expect(BatteryParser.positive(["A": 0, "B": 4200], ["A", "B"]) == 4200)
    #expect(BatteryParser.registry(["AppleRawCurrentCapacity": 0]).currentCapacityMAh == 0)
  }
  @Test func exportedModelNamesCannotBecomeSpreadsheetFormulas() {
    var reading = BatteryReading(id: "test", name: "Test")
    reading.model = "=1+1"
    let csv = BatteryHistoryStore.csv([BatteryHistoryEntry(reading)])
    #expect(csv.contains("\"'=1+1\""))
  }
  @Test func signedCurrentHandles32And64BitWrappedValues() {
    #expect(BatteryParser.signedCurrent(NSNumber(value: UInt64.max - 499)) == -500)
    #expect(BatteryParser.signedCurrent(NSNumber(value: UInt32.max - 499)) == -500)
    #expect(BatteryParser.signedCurrent(-500) == -500)
    #expect(BatteryParser.signedCurrent(0) == 0)
    #expect(BatteryParser.signedCurrent(true) == nil)
  }
  @Test func manufactureDatesAreDecodedWithoutGuessingFromSerialNumbers() throws {
    let packed = ((2020 - 1980) << 9) | (7 << 5) | 15
    let date = try #require(BatteryParser.manufactureDate(packed))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    #expect(calendar.component(.year, from: date) == 2020)
    #expect(calendar.component(.month, from: date) == 7)
    #expect(BatteryParser.manufactureDate(0) == nil)
    #expect(BatteryParser.manufactureDate(65535) == nil)
    #expect(BatteryParser.manufactureDate(((2020 - 1980) << 9) | (2 << 5) | 31) == nil)
  }
  @Test func mobileDiagnosticsMergeHealthWithPublicChargeDomain() {
    let raw: [String: Any] = [
      "Diagnostics": [
        "GasGauge": [
          "CycleCount": 300, "FullChargeCapacity": 2700, "DesignCapacity": 3000,
        ]
      ]
    ]
    let r = BatteryParser.mobile(
      info: ["DeviceName": "Test iPhone", "ProductType": "iPhone10,6"],
      level: ["BatteryCurrentCapacity": 75, "BatteryIsCharging": true, "ExternalConnected": true],
      diagnostics: raw, identifier: "synthetic-device-identifier")
    #expect(r.healthPercent == 90)
    #expect(r.chargePercent == 75)
    #expect(r.cycleCount == 300)
    #expect(r.charging == true)
    #expect(r.model == "iPhone10,6")
    #expect(!r.id.contains("synthetic"))
    #expect(r.id.count == 64)
  }
  @Test func restrictedIOSStillShowsChargeWithoutInventingHealth() {
    let r = BatteryParser.mobile(
      info: [:], level: ["BatteryCurrentCapacity": 40],
      diagnostics: [:], identifier: "synthetic")
    #expect(r.chargePercent == 40)
    #expect(r.healthPercent == nil)
    #expect(r.cycleCount == nil)
  }
  @Test func batteryHistoryPersistsDeduplicatesHourlyAndExportsWithoutSerials() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("history.json")
    let store = BatteryHistoryStore(url: url)
    var r = BatteryReading(id: BatteryReading.privateID("private-serial"), name: "Personal phone")
    r.fullChargeCapacityMAh = 4000
    r.designCapacityMAh = 5000
    r.cycleCount = 50
    store.record(r, automatic: true)
    r.timestamp += 1800
    store.record(r, automatic: true)
    #expect(store.entries.count == 1)
    r.timestamp += 1800
    store.record(r, automatic: true)
    #expect(store.entries.count == 2)
    #expect(BatteryHistoryStore(url: url).entries == store.entries)
    let json = try String(contentsOf: url, encoding: .utf8)
    let csv = BatteryHistoryStore.csv(store.entries)
    #expect(!json.contains("private-serial"))
    #expect(!json.contains("Personal phone"))
    #expect(!csv.contains("private-serial"))
    #expect(csv.contains("80.00,4000.00,5000.00,50"))
    #expect(csv.split(separator: "\n").count == 3)
  }
  @Test func corruptHistoryIsPreservedInsteadOfOverwritten() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("broken".utf8).write(to: url)
    let store = BatteryHistoryStore(url: url)
    var r = BatteryReading(id: "test", name: "Test")
    r.cycleCount = 1
    store.record(r)
    #expect(store.error != nil)
    #expect(try String(contentsOf: url, encoding: .utf8) == "broken")
  }
  @Test func newSettingsPreserveTheExistingUserLayout() throws {
    let domain = "sg.angad.Mica.migration-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    var values = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(Preferences())) as? [String: Any])
    values.removeValue(forKey: "mobileEnabled")
    values.removeValue(forKey: "mobileNetwork")
    values.removeValue(forKey: "batteryHistoryAutomatic")
    values["interval"] = 5.0
    values["compact"] = true
    values["cpuUser"] = "#123456"
    defaults.set(try JSONSerialization.data(withJSONObject: values), forKey: "preferences.v1")
    let settings = Settings(defaults: defaults)
    #expect(settings.value.interval == 5)
    #expect(settings.value.compact)
    #expect(settings.value.cpuUser == "#123456")
    #expect(!settings.value.mobileEnabled)
    #expect(!settings.value.enabled.contains(.battery))
  }
  @Test func highCoreCountMachinesKeepAllCoresAndFitTheMeterBar() {
    var s = Snapshot()
    s.cores = Array(repeating: CoreLoad(user: 0.2, system: 0.1), count: 192)
    #expect(MeterPainter.groupedCores(s.cores).count == 32)
    #expect(MeterPainter.groupedCores(s.cores).allSatisfy { abs($0.total - 0.3) < 0.0001 })
    #expect(MeterPainter.image(s, Preferences(), dark: false).size.width < 600)
  }
  @Test func intelSMCTemperatureDecodingRejectsUnknownFormats() {
    #expect(gm_decode_smc("sp78", [0x2a, 0x80], 2) == 42.5)
    #expect(gm_decode_smc("sp78", [0xff, 0x80], 2) == -0.5)
    #expect(gm_decode_smc("fpe2", [0x0f, 0xa0], 2) == 1000)
    #expect(gm_decode_smc("nope", [0, 0], 2).isNaN)
    #expect(gm_decode_smc("sp78", [0], 1).isNaN)
  }
}
