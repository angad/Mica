import AppKit
import Combine
import Hardware
import ServiceManagement
import SwiftUI

enum Meter: String, CaseIterable, Identifiable, Codable {
  case memory, network, disk, temperature, cpu, input, consumption, battery
  var id: String { rawValue }
  var title: String {
    switch self {
    case .memory: "Memory"
    case .network: "Network"
    case .disk: "Disk"
    case .temperature: "Temperature"
    case .cpu: "CPU"
    case .input: "Charger input"
    case .consumption: "Mac consumption"
    case .battery: "Battery"
    }
  }
  var symbol: String {
    switch self {
    case .memory: "memorychip"
    case .network: "arrow.up.arrow.down"
    case .disk: "internaldrive"
    case .temperature: "thermometer.medium"
    case .cpu: "cpu"
    case .input: "powerplug"
    case .consumption: "bolt.fill"
    case .battery: "battery.100"
    }
  }
  var color: Color {
    switch self {
    case .memory: .purple
    case .network: .green
    case .disk: .orange
    case .temperature: .red
    case .cpu: .blue
    case .input: .meterMint
    case .consumption: .orange
    case .battery: .green
    }
  }
}
enum Pane: String, CaseIterable, Identifiable {
  case cpu = "CPU"
  case memory = "Memory"
  case disk = "Disk"
  case network = "Network"
  case temperature = "Temperature"
  case power = "Power"
  case battery = "Battery"
  case devices = "Devices"
  case general = "General"
  var id: String { rawValue }
  var meter: Meter? {
    switch self {
    case .cpu: .cpu
    case .memory: .memory
    case .disk: .disk
    case .network: .network
    case .temperature: .temperature
    case .battery: .battery
    default: nil
    }
  }
  var symbol: String {
    meter?.symbol
      ?? (self == .power ? "bolt.circle" : self == .devices ? "iphone" : "slider.horizontal.3")
  }
}
struct Preferences: Codable, Equatable {
  var enabled: Set<Meter> = Set(Meter.allCases.filter { $0 != .battery })
  var interval: Double = 1
  var fahrenheit = false
  var networkBits = false
  var networkInterface = "primary"
  var temperatureSensor = "Automatic"
  var cpuPerCore = true
  var cpuPercent = false
  var memoryPercent = false
  var diskRates = false
  var monochrome = false
  var compact = false
  var appearance = "System"
  var mobileEnabled = false
  var mobileNetwork = false
  var batteryHistoryAutomatic = false
  var cpuUser = "#168CFF"
  var cpuSystem = "#FF5349"
  var transmit = "#32D74B"
  var receive = "#FF5349"
}
final class Settings: ObservableObject {
  @Published var value: Preferences {
    didSet {
      if let data = try? JSONEncoder().encode(value) {
        defaults.set(data, forKey: "preferences.v1")
      }
    }
  }
  private let defaults: UserDefaults
  init(defaults: UserDefaults = .standard, legacyDefaults: UserDefaults? = nil) {
    self.defaults = defaults
    let legacy =
      legacyDefaults
      ?? (defaults === UserDefaults.standard
        ? UserDefaults(suiteName: "sg.angad.GlassMeters") : nil)
    let stored = defaults.data(forKey: "preferences.v1") ?? legacy?.data(forKey: "preferences.v1")
    value =
      stored.flatMap { stored in
        // Merge new defaults into old preferences rather than resetting the entire layout.
        guard let baseline = try? JSONEncoder().encode(Preferences()),
          var merged = (try? JSONSerialization.jsonObject(with: baseline)) as? [String: Any],
          let saved = (try? JSONSerialization.jsonObject(with: stored)) as? [String: Any]
        else { return nil }
        merged.merge(saved) { _, stored in stored }
        guard let data = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(Preferences.self, from: data)
      } ?? Preferences()
    if defaults.data(forKey: "preferences.v1") == nil, stored != nil,
      let migrated = try? JSONEncoder().encode(value)
    {
      defaults.set(migrated, forKey: "preferences.v1")
    }
  }
  func visible(_ meter: Meter) -> Binding<Bool> {
    Binding(
      get: { self.value.enabled.contains(meter) },
      set: { on in
        if on { self.value.enabled.insert(meter) } else { self.value.enabled.remove(meter) }
      })
  }
  func reset() { value = Preferences() }
}
struct CoreLoad: Codable {
  var user: Double
  var system: Double
  var total: Double { min(1, max(0, user + system)) }
}
struct Sensor: Codable, Identifiable {
  var name: String
  var celsius: Double
  var id: String { name }
}
struct Snapshot: Codable {
  var timestamp = Date()
  var cores: [CoreLoad] = []
  var memoryTotal: Double = 0, active: Double = 0, wired: Double = 0, compressed: Double = 0,
    inactive: Double = 0, swap: Double = 0
  var pressure: Int32 = 0
  var upload: Double = 0, download: Double = 0, diskRead: Double = 0, diskWrite: Double = 0
  var diskAvailable = false
  var networkAvailable = false
  var interface = "—"
  var interfaces: [String] = []
  var sensors: [Sensor] = []
  var temperature: Double?
  var temperatureName = "Automatic"
  var battery: BatteryReading?
  var inputWatts: Double?, systemWatts: Double?, adapterWatts: Double?, batteryPercent: Double?
  var externalPower = false, charging = false
  var sessionWh: Double = 0, inputWh: Double = 0
  var cpu: Double { cores.isEmpty ? 0 : cores.map(\.total).reduce(0, +) / Double(cores.count) }
  var memoryUsed: Double { min(memoryTotal, active + wired + compressed) }
  var memoryFraction: Double { memoryTotal > 0 ? memoryUsed / memoryTotal : 0 }
  var pressureText: String { pressure == 4 ? "Critical" : pressure == 2 ? "Elevated" : "Normal" }
}
struct HistoryPoint: Identifiable {
  let id = UUID()
  var date: Date
  var cpu: Double
  var memory: Double
  var temperature: Double?
  var input: Double?
  var consumption: Double?
  var upload: Double
  var download: Double
  var read: Double
  var write: Double
}
func cString<T>(_ tuple: T) -> String {
  var copy = tuple
  return withUnsafePointer(to: &copy) {
    $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { String(cString: $0) }
  }
}
func finite(_ value: Double) -> Double? { value.isFinite ? value : nil }
func counterRate(_ current: UInt64, _ previous: UInt64, elapsed: Double) -> Double {
  elapsed > 0 && current >= previous ? Double(current - previous) / elapsed : 0
}
func tickDelta(_ current: UInt64, _ previous: UInt64) -> Double {
  Double(UInt32(truncatingIfNeeded: current) &- UInt32(truncatingIfNeeded: previous))
}
func energyIncrement(previous: Double?, current: Double?, seconds: Double, maxGap: Double) -> Double
{
  guard let previous, let current, previous.isFinite, current.isFinite, previous >= 0, current >= 0,
    seconds > 0, seconds <= maxGap
  else { return 0 }
  return (previous + current) * 0.5 * seconds / 3600
}
func bytes(_ value: Double) -> String {
  ByteCountFormatter.string(fromByteCount: Int64(max(0, value)), countStyle: .binary)
}
func rate(_ value: Double, bits: Bool = false) -> String {
  var number = max(0, value) * (bits ? 8 : 1)
  let units = bits ? ["b/s", "Kb/s", "Mb/s", "Gb/s"] : ["B/s", "KB/s", "MB/s", "GB/s"]
  var i = 0
  while number >= 1000 && i < 3 {
    number /= 1000
    i += 1
  }
  return String(format: i == 0 ? "%.0f%@" : "%.1f%@", number, units[i])
}
func watts(_ value: Double?) -> String { value.map { String(format: "%.1f W", $0) } ?? "— W" }
func temperatureText(_ value: Double?, fahrenheit: Bool) -> String {
  value.map { String(format: "%.1f°%@", fahrenheit ? $0 * 1.8 + 32 : $0, fahrenheit ? "F" : "C") }
    ?? "—°"
}

final class Monitor: ObservableObject {
  @Published var snapshot = Snapshot()
  @Published var history: [HistoryPoint] = []
  @Published var paused = false
  let batteryHistory = BatteryHistoryStore()
  let mobile = MobileBatteryMonitor()
  private var deviceSubscription: AnyCancellable?
  private var deviceOptions: [Bool] = []
  private let queue = DispatchQueue(label: "sg.angad.Mica.sampling", qos: .utility)
  private var timer: Timer?
  private var previous: GMSample?
  private var previousTime: Double?
  private var busy = false
  private let settings: Settings
  private var subscription: AnyCancellable?
  init(settings: Settings, start: Bool = true) {
    self.settings = settings
    if start {
      mobile.onReadings = { [weak self] readings in
        guard let self, self.settings.value.batteryHistoryAutomatic else { return }
        readings.forEach { self.batteryHistory.record($0, automatic: true) }
      }
      deviceSubscription = settings.$value.sink { [weak self] preferences in
        guard let self else { return }
        let options = [preferences.mobileEnabled, preferences.mobileNetwork]
        guard options != self.deviceOptions else { return }
        self.deviceOptions = options
        self.mobile.configure(
          enabled: preferences.mobileEnabled, network: preferences.mobileNetwork)
      }
      restart()
      subscription = settings.$value.map(\.interval).removeDuplicates().dropFirst().sink {
        [weak self] _ in DispatchQueue.main.async { self?.restart() }
      }
    }
  }
  func restart() {
    timer?.invalidate()
    sample()
    timer = Timer.scheduledTimer(withTimeInterval: settings.value.interval, repeats: true) {
      [weak self] _ in self?.sample()
    }
    timer?.tolerance = settings.value.interval * 0.15
  }
  func resetEnergy() {
    snapshot.sessionWh = 0
    snapshot.inputWh = 0
  }
  func togglePause() {
    paused.toggle()
    if !paused {
      previous = nil
      previousTime = nil
      sample()
    }
  }
  func sample() {
    guard !busy, !paused else { return }
    busy = true
    queue.async { [weak self] in
      var raw = GMSample()
      gm_sample(&raw)
      let battery = MacBatteryReader.read()
      let time = ProcessInfo.processInfo.systemUptime
      DispatchQueue.main.async {
        self?.accept(raw, time: time, battery: battery)
        self?.busy = false
      }
    }
  }
  func accept(_ raw: GMSample, time: Double, battery: BatteryReading? = nil) {
    var current = raw
    var s = Snapshot()
    let p = settings.value
    s.battery = battery
    if let battery, p.batteryHistoryAutomatic { batteryHistory.record(battery, automatic: true) }
    let elapsed = previousTime.map { time - $0 } ?? 0
    let validInterval = elapsed > 0 && elapsed <= max(10, p.interval * 3)
    if var old = previous, validInterval, current.cpu_valid != 0,
      current.core_count == old.core_count
    {
      withUnsafeBytes(of: &current.cores) { nowBuffer in
        withUnsafeBytes(of: &old.cores) { oldBuffer in
          let now = nowBuffer.bindMemory(to: GMCore.self)
          let before = oldBuffer.bindMemory(to: GMCore.self)
          for i in 0..<Int(current.core_count) {
            let u = tickDelta(now[i].user, before[i].user) + tickDelta(now[i].nice, before[i].nice)
            let k = tickDelta(now[i].system, before[i].system)
            let idle = tickDelta(now[i].idle, before[i].idle)
            let total = u + k + idle
            s.cores.append(
              CoreLoad(user: total > 0 ? u / total : 0, system: total > 0 ? k / total : 0))
          }
        }
      }
    } else {
      s.cores = Array(repeating: CoreLoad(user: 0, system: 0), count: Int(current.core_count))
    }
    s.memoryTotal = Double(current.memory_total)
    s.active = Double(current.memory_active)
    s.wired = Double(current.memory_wired)
    s.compressed = Double(current.memory_compressed)
    s.inactive = Double(current.memory_inactive)
    s.swap = Double(current.swap_used)
    s.pressure = current.pressure
    var network: [String: (UInt64, UInt64)] = [:]
    withUnsafeBytes(of: &current.interfaces) { buffer in
      for item in buffer.bindMemory(to: GMInterface.self).prefix(Int(current.interface_count)) {
        network[cString(item.name)] = (item.incoming, item.outgoing)
      }
    }
    s.interfaces = network.keys.sorted()
    let primary = cString(current.primary_interface)
    s.interface = p.networkInterface == "primary" ? primary : p.networkInterface
    s.networkAvailable = network[s.interface] != nil
    if var old = previous, validInterval, let now = network[s.interface] {
      withUnsafeBytes(of: &old.interfaces) { buffer in
        for item in buffer.bindMemory(to: GMInterface.self).prefix(Int(old.interface_count))
        where cString(item.name) == s.interface {
          s.download = counterRate(now.0, item.incoming, elapsed: elapsed)
          s.upload = counterRate(now.1, item.outgoing, elapsed: elapsed)
        }
      }
    }
    s.diskAvailable = current.disk_valid != 0
    if let old = previous, validInterval, current.disk_valid != 0, old.disk_valid != 0 {
      s.diskRead = counterRate(current.disk_read, old.disk_read, elapsed: elapsed)
      s.diskWrite = counterRate(current.disk_write, old.disk_write, elapsed: elapsed)
    }
    withUnsafeBytes(of: &current.sensors) { buffer in
      for item in buffer.bindMemory(to: GMSensor.self).prefix(Int(current.sensor_count)) {
        s.sensors.append(Sensor(name: cString(item.name), celsius: item.celsius))
      }
    }
    s.sensors = Dictionary(grouping: s.sensors, by: \.name).map { name, readings in
      Sensor(name: name, celsius: readings.map(\.celsius).max()!)
    }.sorted { $0.name < $1.name }
    s.temperatureName = p.temperatureSensor
    if p.temperatureSensor == "CPU average" {
      let cpuSensors = s.sensors.filter {
        $0.name.localizedCaseInsensitiveContains("pACC")
          || $0.name.localizedCaseInsensitiveContains("eACC")
          || $0.name.localizedCaseInsensitiveContains("CPU")
      }
      if !cpuSensors.isEmpty {
        s.temperature = cpuSensors.map(\.celsius).reduce(0, +) / Double(cpuSensors.count)
      }
    } else {
      let selected = s.sensors.first(where: { $0.name == p.temperatureSensor })
      let automatic =
        s.sensors.first(where: { $0.name == "SOC MTR Temp Sensor0" })
        ?? s.sensors.first(where: { $0.name.localizedCaseInsensitiveContains("CPU die") })
        ?? s.sensors.first(where: { $0.name.localizedCaseInsensitiveContains("CPU") })
        ?? s.sensors.first(where: { $0.name.localizedCaseInsensitiveContains("SOC") })
      let sensor =
        selected
        ?? ((p.temperatureSensor == "Automatic" || p.temperatureSensor == "SOC MTR Temp Sensor0")
          ? automatic : nil)
      s.temperature = sensor?.celsius
      if let sensor { s.temperatureName = sensor.name }
    }
    if s.battery?.temperatureCelsius == nil {
      s.battery?.temperatureCelsius =
        s.sensors.first(where: {
          $0.name.localizedCaseInsensitiveContains("gas gauge battery") || $0.name.contains("TB0T")
        })?.celsius
    }
    s.inputWatts = finite(current.charger_watts)
    s.systemWatts = finite(current.system_watts)
    s.adapterWatts = finite(current.adapter_watts)
    s.batteryPercent = finite(current.battery_percent)
    s.externalPower = current.external_power != 0
    s.charging = current.charging != 0
    s.sessionWh =
      snapshot.sessionWh
      + energyIncrement(
        previous: snapshot.systemWatts, current: s.systemWatts, seconds: elapsed,
        maxGap: max(10, p.interval * 3))
    s.inputWh =
      snapshot.inputWh
      + energyIncrement(
        previous: snapshot.inputWatts, current: s.inputWatts, seconds: elapsed,
        maxGap: max(10, p.interval * 3))
    previous = current
    previousTime = time
    snapshot = s
    if validInterval {
      history.append(
        HistoryPoint(
          date: s.timestamp, cpu: s.cpu * 100, memory: s.memoryFraction * 100,
          temperature: s.temperature, input: s.inputWatts, consumption: s.systemWatts,
          upload: s.upload, download: s.download, read: s.diskRead, write: s.diskWrite))
    }
    if history.count > 120 { history.removeFirst(history.count - 120) }
  }
}
extension NSColor {
  convenience init(hex: String) {
    let n =
      UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x168CFF
    self.init(
      srgbRed: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255,
      blue: CGFloat(n & 255) / 255, alpha: 1)
  }
  var hex: String {
    let c = usingColorSpace(.sRGB) ?? self
    return String(
      format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255),
      Int(c.blueComponent * 255))
  }
}
