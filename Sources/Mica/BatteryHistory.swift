import Combine
import Foundation

struct BatteryHistoryEntry: Codable, Equatable, Identifiable {
  var id = UUID()
  var deviceID: String
  var deviceKind: String
  var model: String?
  var date: Date
  var healthPercent: Double?
  var fullChargeCapacityMAh: Double?
  var designCapacityMAh: Double?
  var cycleCount: Int?
  init(_ reading: BatteryReading) {
    deviceID = reading.id
    deviceKind = reading.kind
    model = reading.model
    date = reading.timestamp
    healthPercent = reading.healthPercent
    fullChargeCapacityMAh = reading.fullChargeCapacityMAh
    designCapacityMAh = reading.designCapacityMAh
    cycleCount = reading.cycleCount
  }
}

final class BatteryHistoryStore: ObservableObject {
  @Published private(set) var entries: [BatteryHistoryEntry] = []
  @Published private(set) var error: String?
  let url: URL
  private var readable = true
  init(url: URL? = nil) {
    self.url =
      url
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Mica/battery-history.json")
    let legacy = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("GlassMeters/battery-history.json")
    let source =
      url == nil && !FileManager.default.fileExists(atPath: self.url.path)
        && FileManager.default.fileExists(atPath: legacy.path) ? legacy : self.url
    guard FileManager.default.fileExists(atPath: source.path) else { return }
    do {
      entries = try JSONDecoder().decode(
        [BatteryHistoryEntry].self, from: Data(contentsOf: source))
      entries = Array(entries.sorted { $0.date < $1.date }.suffix(10_000))
    } catch {
      readable = false
      self.error = "Battery history could not be read. The existing file has been preserved."
    }
  }
  func record(_ reading: BatteryReading, automatic: Bool = false) {
    guard readable else { return }
    guard reading.healthPercent != nil || reading.cycleCount != nil else { return }
    if automatic, let last = entries.last(where: { $0.deviceID == reading.id }),
      reading.timestamp.timeIntervalSince(last.date) < 3600
    {
      return
    }
    var updated = entries
    updated.append(BatteryHistoryEntry(reading))
    updated = Array(updated.sorted { $0.date < $1.date }.suffix(10_000))
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      try JSONEncoder().encode(updated).write(to: url, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
      entries = updated
      error = nil
    } catch { self.error = "Battery history could not be saved: \(error.localizedDescription)" }
  }
  static func csv(_ entries: [BatteryHistoryEntry]) -> String {
    func field(_ s: String) -> String {
      let safe = s.first.map { "=+-@\t\r".contains($0) } == true ? "'" + s : s
      return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    func number(_ n: Double?) -> String {
      n.map { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? ""
    }
    let formatter = ISO8601DateFormatter()
    var rows = [
      "device_id,device_type,model,date,health_percent,full_charge_mah,design_mah,cycle_count"
    ]
    rows += entries.map { entry in
      [
        field(entry.deviceID), field(entry.deviceKind), field(entry.model ?? ""),
        field(formatter.string(from: entry.date)), number(entry.healthPercent),
        number(entry.fullChargeCapacityMAh), number(entry.designCapacityMAh),
        entry.cycleCount.map(String.init) ?? "",
      ].joined(separator: ",")
    }
    return rows.joined(separator: "\n") + "\n"
  }
}
