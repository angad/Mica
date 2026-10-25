import AppKit
import Combine
import Hardware
import SwiftUI

struct ProcessCounter: Codable, Sendable {
  var pid: Int32
  var started: UInt64
  var name: String
  var cpuNanoseconds: UInt64
  var memoryBytes: UInt64
}
struct ProcessBatch: Sendable {
  var time: Double
  var total: Int
  var counters: [ProcessCounter]
}
struct ProcessReading: Identifiable, Codable {
  var pid: Int32
  var started: UInt64
  var name: String
  var cpuPercent: Double?
  var memoryBytes: UInt64
  var id: String { "\(pid)-\(started)" }
}
enum ProcessReader {
  static func read() -> ProcessBatch {
    let capacity = 4096
    let buffer = UnsafeMutablePointer<GMProcess>.allocate(capacity: capacity)
    defer { buffer.deallocate() }
    var total: Int32 = 0
    let count = gm_read_processes(buffer, Int32(capacity), &total)
    let records = (0..<Int(count)).map { i in
      let item = buffer[i]
      return ProcessCounter(
        pid: item.pid, started: item.started, name: cString(item.name),
        cpuNanoseconds: item.cpu_nanoseconds, memoryBytes: item.memory_bytes)
    }
    return ProcessBatch(time: ProcessInfo.processInfo.systemUptime, total: Int(total), counters: records)
  }
  static func readings(_ batch: ProcessBatch, previous: ProcessBatch?) -> [ProcessReading] {
    let old = Dictionary((previous?.counters ?? []).map { ($0.pid, $0) }, uniquingKeysWith: { _, b in b })
    let elapsed = previous.map { batch.time - $0.time } ?? 0
    return batch.counters.map { item in
      var percent: Double?
      if elapsed > 0, elapsed <= 10, let before = old[item.pid],
        item.started != 0, before.started == item.started,
        item.cpuNanoseconds >= before.cpuNanoseconds {
        percent = Double(item.cpuNanoseconds - before.cpuNanoseconds) / 1e9 / elapsed * 100
      }
      return ProcessReading(
        pid: item.pid, started: item.started, name: item.name,
        cpuPercent: percent, memoryBytes: item.memoryBytes)
    }
  }
}

final class ProcessMonitor: ObservableObject {
  @Published private(set) var readings: [ProcessReading] = []
  @Published private(set) var total = 0
  @Published private(set) var paused = false
  private(set) var viewers: Set<String> = []
  private var previous: ProcessBatch?
  private var timer: Timer?
  private var busy = false
  private var generation = 0
  private let queue = DispatchQueue(label: "sg.angad.Mica.processes", qos: .utility)
  private let reader: @Sendable () -> ProcessBatch
  var isPolling: Bool { timer != nil }
  init(reader: @escaping @Sendable () -> ProcessBatch = { ProcessReader.read() }) { self.reader = reader }
  func setVisible(_ visible: Bool, viewer: String) {
    let wasActive = !viewers.isEmpty
    if visible { viewers.insert(viewer) } else { viewers.remove(viewer) }
    if wasActive != !viewers.isEmpty { restart() }
  }
  func setPaused(_ value: Bool) { paused = value; restart() }
  private func restart() {
    timer?.invalidate(); timer = nil
    generation += 1; busy = false; previous = nil; readings = []
    guard !viewers.isEmpty, !paused else { return }
    sample()
    timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
    timer?.tolerance = 0.3
  }
  private func sample() {
    guard !busy, !viewers.isEmpty, !paused else { return }
    busy = true
    let token = generation
    let read = reader
    queue.async { [weak self] in
      let batch = read()
      DispatchQueue.main.async {
        guard let self, self.generation == token, !self.viewers.isEmpty, !self.paused else { return }
        self.readings = ProcessReader.readings(batch, previous: self.previous)
        self.total = batch.total
        self.previous = batch
        self.busy = false
      }
    }
  }
  func top(memory: Bool) -> [ProcessReading] {
    Array(readings.filter { memory ? $0.memoryBytes > 0 : $0.cpuPercent != nil }.sorted {
      let lhs = memory ? Double($0.memoryBytes) : ($0.cpuPercent ?? 0)
      let rhs = memory ? Double($1.memoryBytes) : ($1.cpuPercent ?? 0)
      return lhs == rhs ? $0.pid < $1.pid : lhs > rhs
    }.prefix(5))
  }
  deinit { timer?.invalidate() }
}

struct TopProcessesView: View {
  @ObservedObject var processes: ProcessMonitor
  var memory: Bool
  var viewer: String
  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        Text(memory ? "Top processes by memory" : "Top processes by CPU").font(.system(size: 12, weight: .semibold))
        Spacer()
        Button("Activity Monitor") {
          NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
        }.buttonStyle(.plain).font(.system(size: 10)).foregroundColor(.secondary)
      }
      let rows = processes.top(memory: memory)
      if rows.isEmpty {
        Text(processes.paused ? "Process sampling is paused." : "Sampling process usage…")
          .font(.system(size: 11)).foregroundColor(.secondary)
      }
      ForEach(rows) { row in
        HStack(spacing: 8) {
          Text(row.name).lineLimit(1).truncationMode(.middle)
          Text("\(row.pid)").foregroundColor(.secondary).font(.system(size: 9))
          Spacer(minLength: 8)
          Text(memory ? bytes(Double(row.memoryBytes)) : String(format: "%.1f%%", row.cpuPercent ?? 0))
            .monospacedDigit()
        }.font(.system(size: 11))
      }
      Text(memory
        ? "Physical memory footprint. macOS may restrict some processes."
        : "100% CPU is one core. macOS may restrict some processes.")
        .font(.system(size: 9)).foregroundColor(.secondary)
    }
    .onAppear { processes.setVisible(true, viewer: viewer) }
    .onDisappear { processes.setVisible(false, viewer: viewer) }
  }
}
