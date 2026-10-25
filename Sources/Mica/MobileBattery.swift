import Combine
import Foundation

protocol DeviceCommandRunning {
  func run(_ tool: String, _ arguments: [String]) throws -> Data
}
enum DeviceReadError: LocalizedError {
  case missingTools, timeout, unavailable
  var errorDescription: String? {
    switch self {
    case .missingTools: return "Install libimobiledevice to read paired iPhones and iPads."
    case .timeout: return "The device did not respond. Unlock it and check the cable or pairing."
    case .unavailable:
      return "Device diagnostics are unavailable. Unlock the device and trust this Mac in Finder."
    }
  }
}
/// Invoke installed, unmodified libimobiledevice tools. Nothing pairs, reboots,
/// writes to a device, installs dependencies, or contacts an external service.
struct DeviceCommandRunner: DeviceCommandRunning {
  static func executable(_ name: String) -> URL? {
    for directory in ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin"] {
      let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
      if FileManager.default.isExecutableFile(atPath: url.path) { return url }
    }
    return nil
  }
  func run(_ tool: String, _ arguments: [String]) throws -> Data {
    guard ["idevice_id", "ideviceinfo", "idevicediagnostics"].contains(tool),
      let executable = Self.executable(tool)
    else { throw DeviceReadError.missingTools }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let output = directory.appendingPathComponent("output")
    FileManager.default.createFile(
      atPath: output.path, contents: nil,
      attributes: [.posixPermissions: 0o600])
    let handle = try FileHandle(forWritingTo: output)
    defer { try? handle.close() }
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = handle
    process.standardError = FileHandle.nullDevice
    try process.run()
    let deadline = Date().addingTimeInterval(5)
    while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.025) }
    if process.isRunning {
      process.terminate()
      let grace = Date().addingTimeInterval(0.25)
      while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.01) }
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
      process.waitUntilExit()
      throw DeviceReadError.timeout
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw DeviceReadError.unavailable }
    let size =
      (try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.intValue
      ?? 0
    guard size < 4_000_000 else { throw DeviceReadError.unavailable }
    return try Data(contentsOf: output)
  }
}
struct MobileBatteryResult: Identifiable {
  var id: String
  var reading: BatteryReading?
  var message: String?
}
struct MobileBatteryScanner {
  var runner: DeviceCommandRunning = DeviceCommandRunner()
  func scan(network: Bool = false) throws -> [MobileBatteryResult] {
    let usb = try runner.run("idevice_id", ["-l"])
    var devices = identifiers(usb).map { ($0, false) }
    if network {
      let wireless = try runner.run("idevice_id", ["-n"])
      let seen = Set(devices.map(\.0))
      devices += identifiers(wireless).filter { !seen.contains($0) }.map { ($0, true) }
    }
    return devices.prefix(8).map { identifier, wireless in
      let base = ["-u", identifier] + (wireless ? ["-n"] : [])
      do {
        let info = try plist(runner.run("ideviceinfo", base + ["-x"]))
        let level =
          (try? plist(
            runner.run("ideviceinfo", base + ["-x", "-q", "com.apple.mobile.battery"]))) ?? [:]
        var diagnostic: [String: Any] = [:]
        // Some iOS releases withhold GasGauge; still show level/charging.
        if let data = try? runner.run("idevicediagnostics", base + ["diagnostics", "GasGauge"]),
          let value = try? plist(data)
        {
          diagnostic = value
        }
        for entry in ["AppleSmartBattery", "AppleARMPMUCharger"] {
          if BatteryParser.findDictionary(diagnostic, containing: ["DesignCapacity"]) != nil {
            break
          }
          if let data = try? runner.run("idevicediagnostics", base + ["ioregentry", entry]),
            let registry = try? plist(data)
          {
            diagnostic[entry] = registry
          }
        }
        let r = BatteryParser.mobile(
          info: info, level: level, diagnostics: diagnostic, identifier: identifier)
        return MobileBatteryResult(
          id: r.id, reading: r,
          message: r.healthPercent == nil
            ? "This iOS version does not expose capacity health. Charge and charging state remain available."
            : nil)
      } catch {
        return MobileBatteryResult(
          id: BatteryReading.privateID(identifier), reading: nil,
          message: error.localizedDescription)
      }
    }
  }
  private func identifiers(_ data: Data) -> [String] {
    Array(
      Set(
        String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
          .map(String.init).filter {
            $0.range(of: "^[A-Fa-f0-9-]{8,64}$", options: .regularExpression) != nil
          })
    ).sorted()
  }
  private func plist(_ data: Data) throws -> [String: Any] {
    guard
      let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        as? [String: Any]
    else { throw DeviceReadError.unavailable }
    return value
  }
}
final class MobileBatteryMonitor: ObservableObject {
  @Published private(set) var devices: [MobileBatteryResult] = []
  @Published private(set) var scanning = false
  @Published private(set) var message: String?
  var onReadings: (([BatteryReading]) -> Void)?
  private let queue = DispatchQueue(label: "sg.angad.Mica.devices", qos: .utility)
  private var timer: Timer?
  private var network = false
  private var generation = 0
  func configure(enabled: Bool, network: Bool) {
    timer?.invalidate()
    timer = nil
    self.network = network
    generation += 1
    if enabled {
      refresh()
      timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
        self?.refresh()
      }
      timer?.tolerance = 5
    } else {
      devices = []
      message = nil
    }
  }
  func refresh() {
    guard !scanning else { return }
    scanning = true
    let generation = self.generation
    let wireless = network
    queue.async { [weak self] in
      let result = Result { try MobileBatteryScanner().scan(network: wireless) }
      DispatchQueue.main.async {
        guard let self else { return }
        self.scanning = false
        guard generation == self.generation else { return }
        switch result {
        case .success(let devices):
          self.devices = devices
          self.message =
            devices.isEmpty
            ? "No paired devices found. Connect and unlock an iPhone or iPad, then trust this Mac in Finder."
            : nil
          self.onReadings?(devices.compactMap(\.reading))
        case .failure(let error):
          self.devices = []
          self.message = error.localizedDescription
        }
      }
    }
  }
  deinit { timer?.invalidate() }
}
