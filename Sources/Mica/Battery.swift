import CryptoKit
import Foundation
import IOKit
import IOKit.ps

struct BatteryReport: Encodable {
  let appVersion = AppVersion.current
  let battery: BatteryReading
  let healthPercent: Double?
  init(_ battery: BatteryReading) {
    self.battery = battery
    healthPercent = battery.healthPercent
  }
}

/// Values describe what the hardware reported; absence is never represented as zero.
struct BatteryReading: Codable, Equatable, Identifiable {
  var id: String
  var name: String
  var kind = "Mac"
  var model: String?
  var operatingSystem: String?
  var timestamp = Date()
  var chargePercent: Double?
  var currentCapacityMAh: Double?
  var fullChargeCapacityMAh: Double?
  var designCapacityMAh: Double?
  var cycleCount: Int?
  var temperatureCelsius: Double?
  var voltage: Double?
  var currentMA: Double?
  var manufacturer: String?
  var manufactureDate: Date?
  var condition: String?
  var externalPower: Bool?
  var charging: Bool?
  var timeToEmptyMinutes: Int?
  var timeToFullMinutes: Int?
  var source = "IOKit"

  var healthPercent: Double? {
    guard let full = fullChargeCapacityMAh, let design = designCapacityMAh,
      full.isFinite, design.isFinite, full > 0, design > 0, full / design <= 2
    else { return nil }
    return full / design * 100
  }
  var batteryWatts: Double? {
    guard let voltage, let currentMA else { return nil }
    return voltage * currentMA / 1000
  }
  var state: String {
    if charging == true { return "Charging" }
    if externalPower == true { return "Connected · not charging" }
    if externalPower == false { return "On battery" }
    return "Unknown"
  }
  var timeEstimate: (label: String, minutes: Int)? {
    if charging == true, let minutes = timeToFullMinutes, minutes > 0 {
      return ("Estimated time to full", minutes)
    }
    if externalPower == false, charging != true, let minutes = timeToEmptyMinutes, minutes > 0 {
      return ("Estimated time remaining", minutes)
    }
    return nil
  }
  static func privateID(_ identifier: String) -> String {
    SHA256.hash(data: Data(identifier.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

enum BatteryParser {
  static func number(_ dictionary: [String: Any], _ keys: [String]) -> Double? {
    for key in keys {
      guard let n = dictionary[key] as? NSNumber,
        CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite
      else { continue }
      return n.doubleValue
    }
    return nil
  }
  static func positive(_ dictionary: [String: Any], _ keys: [String]) -> Double? {
    for key in keys {
      if let n = number(dictionary, [key]), n > 0, n < 1_000_000 { return n }
    }
    return nil
  }
  static func capacity(_ dictionary: [String: Any], _ keys: [String]) -> Double? {
    for key in keys {
      if let n = number(dictionary, [key]), n >= 0, n < 1_000_000 { return n }
    }
    return nil
  }
  static func flag(_ dictionary: [String: Any], _ keys: [String]) -> Bool? {
    for key in keys {
      if let n = dictionary[key] as? NSNumber { return n.boolValue }
    }
    return nil
  }
  static func signedCurrent(_ value: Any?) -> Double? {
    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
    var signed = n.int64Value
    if signed > Int64(Int32.max), signed <= Int64(UInt32.max) {
      signed = Int64(Int32(bitPattern: UInt32(signed)))
    }
    guard abs(Double(signed)) < 100_000 else { return nil }
    return Double(signed)
  }
  static func manufactureDate(_ value: Any?, now: Date = Date()) -> Date? {
    guard let n = value as? NSNumber else { return nil }
    let packed = n.intValue
    guard packed > 0, packed < 65535 else { return nil }
    let day = packed & 31
    let month = (packed >> 5) & 15
    let year = 1980 + (packed >> 9)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let components = DateComponents(year: year, month: month, day: day)
    guard (1...12).contains(month), (1...31).contains(day),
      let date = calendar.date(from: components), date <= now,
      calendar.component(.year, from: date) == year,
      calendar.component(.month, from: date) == month,
      calendar.component(.day, from: date) == day
    else { return nil }
    return date
  }
  /// Apple Silicon's CurrentCapacity/MaxCapacity are percentages, while older Intel
  /// batteries use mAh. Never divide a percentage by a design capacity in mAh.
  static func registry(
    _ properties: [String: Any], id: String = "mac-local",
    name: String = "This Mac", kind: String = "Mac"
  ) -> BatteryReading {
    let details = properties["BatteryData"] as? [String: Any] ?? [:]
    var r = BatteryReading(id: id, name: name, kind: kind)
    r.designCapacityMAh =
      positive(details, ["DesignCapacity"])
      ?? positive(properties, ["DesignCapacity"])
    r.fullChargeCapacityMAh =
      positive(details, ["FullChargeCapacity", "NominalChargeCapacity"])
      ?? positive(
        properties, ["AppleRawMaxCapacity", "FullChargeCapacity", "NominalChargeCapacity"])
    let maximum = positive(properties, ["MaxCapacity"])
    if r.fullChargeCapacityMAh == nil, let maximum, maximum > 100 {
      r.fullChargeCapacityMAh = maximum
    }
    r.currentCapacityMAh =
      capacity(properties, ["AppleRawCurrentCapacity"])
      ?? capacity(details, ["RemainingCapacity"])
    let current = number(properties, ["CurrentCapacity"])
    if let maximum, let current, current >= 0, current <= maximum {
      r.chargePercent = current / maximum * 100
      if maximum > 100 { r.currentCapacityMAh = current }
    } else if let current = r.currentCapacityMAh, let maximum = r.fullChargeCapacityMAh,
      current <= maximum
    {
      r.chargePercent = current / maximum * 100
    }
    if let cycles = number(properties, ["CycleCount"]) ?? number(details, ["CycleCount"]),
      cycles >= 0, cycles < 100_000
    {
      r.cycleCount = Int(cycles)
    }
    if let raw = positive(properties, ["Temperature"]) {
      let c = raw / 10 - 273.15
      if (-30...100).contains(c) { r.temperatureCelsius = c }
    }
    if let raw = positive(properties, ["Voltage"]), raw < 100_000 { r.voltage = raw / 1000 }
    r.currentMA = signedCurrent(properties["InstantAmperage"] ?? properties["Amperage"])
    r.manufacturer = properties["Manufacturer"] as? String
    r.manufactureDate = manufactureDate(properties["ManufactureDate"])
    r.condition = properties["BatteryHealth"] as? String
    r.externalPower = flag(properties, ["ExternalConnected"])
    r.charging = flag(properties, ["IsCharging"])
    r.timeToEmptyMinutes = minutes(properties, "AvgTimeToEmpty")
    r.timeToFullMinutes = minutes(properties, "AvgTimeToFull")
    return r
  }
  static func minutes(_ dictionary: [String: Any], _ key: String) -> Int? {
    guard let n = number(dictionary, [key]), n > 0, n < 65535 else { return nil }
    return Int(n)
  }
  static func mobile(
    info: [String: Any], level: [String: Any], diagnostics: [String: Any],
    identifier: String
  ) -> BatteryReading {
    let name = info["DeviceName"] as? String ?? "iPhone / iPad"
    let registry = findDictionary(
      diagnostics, containing: ["DesignCapacity", "AppleRawMaxCapacity"])
    let gauge = findDictionary(diagnostics, containing: ["FullChargeCapacity", "CycleCount"])
    var r = self.registry(
      registry ?? [:], id: BatteryReading.privateID(identifier), name: name,
      kind: "iPhone / iPad")
    if let gauge {
      r.designCapacityMAh = r.designCapacityMAh ?? positive(gauge, ["DesignCapacity"])
      r.fullChargeCapacityMAh =
        r.fullChargeCapacityMAh
        ?? positive(gauge, ["FullChargeCapacity", "NominalChargeCapacity"])
      if r.cycleCount == nil, let c = number(gauge, ["CycleCount"]), c >= 0, c < 100_000 {
        r.cycleCount = Int(c)
      }
    }
    if let percent = number(level, ["BatteryCurrentCapacity"]), (0...100).contains(percent) {
      r.chargePercent = percent
    }
    r.charging = flag(level, ["BatteryIsCharging"]) ?? r.charging
    r.externalPower = flag(level, ["ExternalConnected"]) ?? r.externalPower
    r.model = info["ProductType"] as? String
    r.operatingSystem = info["ProductVersion"] as? String
    r.source = "Paired device · libimobiledevice"
    return r
  }
  static func findDictionary(_ value: Any, containing keys: [String]) -> [String: Any]? {
    if let d = value as? [String: Any] {
      if keys.contains(where: { d[$0] is NSNumber }) { return d }
      for key in d.keys.sorted() {
        if let match = findDictionary(d[key]!, containing: keys) { return match }
      }
    } else if let a = value as? [Any] {
      for value in a { if let match = findDictionary(value, containing: keys) { return match } }
    }
    return nil
  }
}

enum MacBatteryReader {
  static let model: String? = {
    var size = 0
    guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
    return String(cString: buffer)
  }()
  static func read() -> BatteryReading? {
    let service = IOServiceGetMatchingService(0, IOServiceMatching("AppleSmartBattery"))
    var reading: BatteryReading?
    if service != 0 {
      defer { IOObjectRelease(service) }
      var props: Unmanaged<CFMutableDictionary>?
      if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
        let properties = props?.takeRetainedValue() as? [String: Any]
      {
        let serial =
          properties["BatterySerialNumber"] as? String
          ?? properties["Serial"] as? String ?? "mac-local"
        reading = BatteryParser.registry(properties, id: BatteryReading.privateID(serial))
      }
    }
    reading?.model = model
    reading?.operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
    // Public IOPS fallback supports older batteries without AppleSmartBattery.
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else { return reading }
    for source in sources {
      guard
        let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
          as? [String: Any], d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
      else { continue }
      var r = reading ?? BatteryReading(id: "mac-local", name: "This Mac")
      let current = BatteryParser.number(d, [kIOPSCurrentCapacityKey])
      let max = BatteryParser.positive(d, [kIOPSMaxCapacityKey])
      if r.chargePercent == nil, let current, let max, (0...max).contains(current) {
        r.chargePercent = current / max * 100
      }
      r.condition = r.condition ?? d["BatteryHealth"] as? String
      r.charging = r.charging ?? BatteryParser.flag(d, [kIOPSIsChargingKey])
      r.externalPower =
        r.externalPower ?? (d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
      r.timeToEmptyMinutes = r.timeToEmptyMinutes ?? BatteryParser.minutes(d, kIOPSTimeToEmptyKey)
      r.timeToFullMinutes =
        r.timeToFullMinutes ?? BatteryParser.minutes(d, kIOPSTimeToFullChargeKey)
      r.model = model
      r.operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
      return r
    }
    return reading
  }
}
