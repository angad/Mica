import Foundation
import Testing

@testable import Mica

@Suite struct MobileBatteryTests {
  @Test func scannerUsesReadOnlyCommandsAndDeduplicatesNetworkDevices() throws {
    let runner = FakeDeviceRunner()
    let results = try MobileBatteryScanner(runner: runner).scan(network: true)
    #expect(results.count == 1)
    #expect(results.first?.reading?.healthPercent == 90)
    #expect(
      runner.calls.allSatisfy {
        !$0.1.contains("restart") && !$0.1.contains("sleep") && !$0.1.contains("shutdown")
      })
    #expect(runner.calls.filter { $0.0 == "ideviceinfo" && !$0.1.contains("-q") }.count == 1)
  }
  @Test func disconnectedAndUntrustedDevicesAreExplicit() throws {
    let empty = FakeDeviceRunner()
    empty.empty = true
    #expect(try MobileBatteryScanner(runner: empty).scan().isEmpty)
    let locked = FakeDeviceRunner()
    locked.locked = true
    let result = try #require(MobileBatteryScanner(runner: locked).scan().first)
    #expect(result.reading == nil)
    #expect(result.message?.contains("Unlock") == true)
  }
  @Test func diagnosticsFailureRetainsLevelInsteadOfDroppingTheDevice() throws {
    let runner = FakeDeviceRunner()
    runner.diagnosticsUnavailable = true
    let result = try #require(MobileBatteryScanner(runner: runner).scan().first)
    #expect(result.reading?.chargePercent == 60)
    #expect(result.reading?.healthPercent == nil)
    #expect(result.message != nil)
  }
}
private final class FakeDeviceRunner: DeviceCommandRunning {
  var calls: [(String, [String])] = []
  var empty = false, locked = false, diagnosticsUnavailable = false
  func run(_ tool: String, _ arguments: [String]) throws -> Data {
    calls.append((tool, arguments))
    if tool == "idevice_id" {
      return Data((empty ? "" : "0123456789abcdef0123456789abcdef01234567\n").utf8)
    }
    if locked { throw DeviceReadError.unavailable }
    let value: [String: Any]
    if tool == "ideviceinfo" {
      value =
        arguments.contains("-q")
        ? ["BatteryCurrentCapacity": 60, "BatteryIsCharging": false]
        : ["DeviceName": "Fixture iPhone", "ProductType": "iPhone8,1"]
    } else {
      if diagnosticsUnavailable { throw DeviceReadError.unavailable }
      value = [
        "Diagnostics": [
          "GasGauge": ["DesignCapacity": 2000, "FullChargeCapacity": 1800, "CycleCount": 100]
        ]
      ]
    }
    return try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
  }
}
