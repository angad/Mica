import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BatteryDetailsView: View {
  var reading: BatteryReading
  var compact = false
  private func capacity(_ n: Double?) -> String {
    n.map { String(format: "%.0f mAh", $0) } ?? "Unavailable"
  }
  private func value(_ label: String, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label).foregroundColor(.secondary)
      Spacer(minLength: 10)
      Text(text).monospacedDigit().multilineTextAlignment(.trailing)
    }.font(.system(size: compact ? 11 : 12))
  }
  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 8 : 12) {
      HStack(alignment: .firstTextBaseline) {
        Text(reading.healthPercent.map { String(format: "%.1f%%", $0) } ?? "—")
          .font(.system(size: compact ? 27 : 36, weight: .medium, design: .rounded))
          .monospacedDigit()
        Text("of design capacity").font(.system(size: 11)).foregroundColor(.secondary)
      }
      if let health = reading.healthPercent {
        ProgressView(value: min(1, health / 100)).accentColor(health < 80 ? .orange : .green)
      }
      value(
        "Charge",
        reading.chargePercent.map { String(format: "%.0f%% · %@", $0, reading.state) }
          ?? reading.state)
      value("Full charge capacity", capacity(reading.fullChargeCapacityMAh))
      value("Design capacity", capacity(reading.designCapacityMAh))
      value("Cycle count", reading.cycleCount.map(String.init) ?? "Unavailable")
      if !compact {
        value("Current capacity", capacity(reading.currentCapacityMAh))
        value("Battery temperature", temperatureText(reading.temperatureCelsius, fahrenheit: false))
        value("Voltage", reading.voltage.map { String(format: "%.3f V", $0) } ?? "Unavailable")
        value(
          "Battery current",
          reading.currentMA.map { String(format: "%+.0f mA", $0) } ?? "Unavailable")
        value(
          "Battery power",
          reading.batteryWatts.map { String(format: "%+.2f W", $0) } ?? "Unavailable")
        if let estimate = reading.timeEstimate {
          value(estimate.label, "\(estimate.minutes / 60)h \(estimate.minutes % 60)m")
        }
        if reading.kind == "Mac", let model = reading.model { value("Mac model", model) }
        if let condition = reading.condition { value("Reported condition", condition) }
        if let maker = reading.manufacturer, !maker.isEmpty { value("Manufacturer", maker) }
        if let date = reading.manufactureDate {
          value(
            "Battery manufacture date",
            DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none))
        }
      }
      Text(
        "Health is full-charge capacity ÷ design capacity. Readings are estimates from the battery controller and can fluctuate. Missing fields are not reported by this device."
      )
      .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(
        horizontal: false, vertical: true)
    }
  }
}

struct BatteryPanel: View {
  @ObservedObject var monitor: Monitor
  @ObservedObject var settings: Settings
  @ObservedObject var history: BatteryHistoryStore
  @ViewState private var exportError: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let battery = monitor.snapshot.battery {
        BatteryDetailsView(reading: battery).padding(16).meterGlass(radius: 16)
        HStack {
          Button("Save health snapshot") { history.record(battery) }
          Button("Export battery report…") { exportReport(battery) }
        }
      } else {
        Label("No internal battery detected", systemImage: "desktopcomputer").font(.headline)
        Text(
          "Desktops can still show CPU, memory, network, storage and supported thermal/power sensors. Connected iPhones and iPads appear under Devices."
        )
        .font(.system(size: 12)).foregroundColor(.secondary)
      }
      Toggle("Save hourly health snapshots", isOn: $settings.value.batteryHistoryAutomatic)
        .toggleStyle(.switch)
      Text(
        "History stays on this Mac. Raw serial numbers and device identifiers are excluded. History holds up to 10,000 snapshots across your devices."
      )
      .font(.system(size: 10)).foregroundColor(.secondary)
      Divider()
      HStack {
        Text("Battery health history").font(.headline)
        Spacer()
        Button("Export history CSV…") { exportHistory() }.disabled(history.entries.isEmpty)
      }
      let entries = history.entries.filter { $0.deviceID == monitor.snapshot.battery?.id }
      if entries.isEmpty {
        Text("Save a snapshot to start tracking capacity and cycles over time.")
          .font(.system(size: 12)).foregroundColor(.secondary)
      } else {
        BatteryHealthChart(entries: entries).frame(height: 90)
        ForEach(Array(entries.suffix(6).reversed())) { entry in
          HStack {
            Text(
              DateFormatter.localizedString(from: entry.date, dateStyle: .medium, timeStyle: .short)
            )
            Spacer()
            Text(entry.healthPercent.map { String(format: "%.1f%%", $0) } ?? "—")
            Text(entry.cycleCount.map { "· \($0) cycles" } ?? "")
          }.font(.system(size: 11)).monospacedDigit()
        }
      }
      if let message = exportError ?? history.error {
        Text(message).font(.system(size: 11)).foregroundColor(.red)
      }
    }
  }
  private func exportHistory() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Mica-battery-history.csv"
    panel.allowedContentTypes = [.commaSeparatedText]
    if panel.runModal() == .OK, let url = panel.url {
      do {
        try BatteryHistoryStore.csv(history.entries).write(
          to: url, atomically: true, encoding: .utf8)
        exportError = nil
      } catch { exportError = error.localizedDescription }
    }
  }
  private func exportReport(_ reading: BatteryReading) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Mica-battery-report.json"
    panel.allowedContentTypes = [.json]
    if panel.runModal() == .OK, let url = panel.url {
      do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(BatteryReport(reading)).write(to: url, options: .atomic)
        exportError = nil
      } catch { exportError = error.localizedDescription }
    }
  }
}

struct MobileBatteryPanel: View {
  @ObservedObject var mobile: MobileBatteryMonitor
  @ObservedObject var settings: Settings
  @ObservedObject var history: BatteryHistoryStore
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Toggle("Monitor paired iPhones and iPads", isOn: $settings.value.mobileEnabled).toggleStyle(
        .switch)
      Toggle("Include devices paired over Wi-Fi", isOn: $settings.value.mobileNetwork)
        .toggleStyle(.switch).disabled(!settings.value.mobileEnabled)
      HStack {
        Button(mobile.scanning ? "Reading devices…" : "Refresh devices") { mobile.refresh() }
          .disabled(mobile.scanning)
        Text("Automatic refresh every 30 seconds when enabled.").font(.system(size: 10))
          .foregroundColor(.secondary)
      }
      Text(
        "Requires the optional libimobiledevice tools. Install with brew install libimobiledevice. Pair and trust devices using Finder first; Mica never pairs or changes a device. Wi-Fi requires existing network pairing."
      )
      .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(
        horizontal: false, vertical: true)
      if let message = mobile.message {
        Text(message).font(.system(size: 12)).foregroundColor(.secondary)
      }
      ForEach(mobile.devices) { device in
        VStack(alignment: .leading, spacing: 12) {
          if let reading = device.reading {
            HStack {
              Label(reading.name, systemImage: "iphone").font(.headline)
              Spacer()
              Text(
                [reading.model, reading.operatingSystem.map { "iOS / iPadOS \($0)" }]
                  .compactMap { $0 }.joined(separator: " · ")
              ).font(.system(size: 10)).foregroundColor(.secondary)
            }
            BatteryDetailsView(reading: reading)
            Button("Save health snapshot") { history.record(reading) }
              .disabled(reading.healthPercent == nil && reading.cycleCount == nil)
            let saved = history.entries.filter { $0.deviceID == reading.id }
            if !saved.isEmpty { BatteryHealthChart(entries: saved).frame(height: 70) }
          }
          if let message = device.message {
            Text(message).font(.system(size: 11)).foregroundColor(.secondary)
          }
        }.padding(16).meterGlass(radius: 16)
      }
    }
  }
}

struct BatteryHealthChart: View {
  var entries: [BatteryHistoryEntry]
  var body: some View {
    GeometryReader { geometry in
      let values = entries.compactMap(\.healthPercent)
      Path { path in
        for (i, value) in values.enumerated() {
          let point = CGPoint(
            x: geometry.size.width * Double(i) / Double(max(1, values.count - 1)),
            y: geometry.size.height * (1 - min(120, max(0, value)) / 120))
          if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
          if values.count == 1 { path.addLine(to: CGPoint(x: point.x + 3, y: point.y)) }
        }
      }.stroke(Color.green, lineWidth: 2)
    }.accessibilityLabel("Battery health history, \(entries.count) saved readings")
  }
}
