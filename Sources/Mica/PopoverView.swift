import AppKit
import SwiftUI

struct PopoverView: View {
  @ObservedObject var settings: Settings
  @ObservedObject var monitor: Monitor
  var meter: Meter
  var openSettings: () -> Void
  var width: CGFloat = 320
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 9) {
        Image(systemName: meter.symbol).font(.system(size: 17, weight: .medium)).foregroundColor(
          meter.color
        ).frame(width: 30, height: 30).meterGlass(tint: meter.color.opacity(0.1), radius: 10)
        VStack(alignment: .leading, spacing: 2) {
          Text(meter.title).font(.system(size: 15, weight: .semibold))
          Text(monitor.paused ? "Updates paused" : "Live on your Mac").font(.system(size: 10))
            .foregroundColor(.secondary)
        }
        Spacer()
        Button(action: openSettings) { Image(systemName: "gearshape").frame(width: 27, height: 27) }
          .buttonStyle(MeterButtonStyle()).help("Mica Settings")
      }
      HStack(alignment: .firstTextBaseline, spacing: 7) {
        Text(headline).font(.system(size: 30, weight: .medium, design: .rounded)).monospacedDigit()
          .meterNumericTransition().lineLimit(1).minimumScaleFactor(0.75)
        if let unit { Text(unit).font(.system(size: 13)).foregroundColor(.secondary) }
      }
      HistoryChart(monitor: monitor, meter: meter).frame(height: 64)
      Divider()
      VStack(spacing: 8) { details }
      HStack {
        Text(
          "Updated \(DateFormatter.localizedString(from: monitor.snapshot.timestamp, dateStyle: .none, timeStyle: .medium))"
        ).font(
          .system(size: 9)
        ).foregroundColor(Color(NSColor.tertiaryLabelColor))
        Spacer()
        Button("Settings…", action: openSettings).buttonStyle(.plain).font(.system(size: 11))
          .foregroundColor(.secondary)
      }
    }.padding(16).frame(width: width).fixedSize(horizontal: false, vertical: true).background(
      Color(NSColor.windowBackgroundColor))
  }
  private var s: Snapshot { monitor.snapshot }
  private var headline: String {
    switch meter {
    case .cpu: String(format: "%.1f%%", s.cpu * 100)
    case .memory: bytes(s.memoryUsed)
    case .network: rate(s.download, bits: settings.value.networkBits)
    case .disk: rate(s.diskRead + s.diskWrite)
    case .temperature: temperatureText(s.temperature, fahrenheit: settings.value.fahrenheit)
    case .input: watts(s.inputWatts)
    case .consumption: watts(s.systemWatts)
    case .battery: s.battery?.chargePercent.map { String(format: "%.0f%%", $0) } ?? "—"
    }
  }
  private var unit: String? {
    switch meter {
    case .cpu: "in use"
    case .memory: "of \(bytes(s.memoryTotal))"
    case .network: "download"
    case .disk: "read + write"
    case .temperature: nil
    case .input: "from charger"
    case .consumption: "system draw"
    case .battery: "charge"
    }
  }
  @ViewBuilder private var details: some View {
    switch meter {
    case .cpu:
      item("Logical cores", "\(s.cores.count)")
      item(
        "User",
        String(
          format: "%.1f%%", s.cores.map(\.user).reduce(0, +) / Double(max(1, s.cores.count)) * 100),
        .blue)
      item(
        "System",
        String(
          format: "%.1f%%", s.cores.map(\.system).reduce(0, +) / Double(max(1, s.cores.count)) * 100
        ), .red)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 25), spacing: 5)], spacing: 8) {
        ForEach(Array(s.cores.enumerated()), id: \.offset) { i, core in
          VStack(spacing: 4) {
            GeometryReader { g in
              ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3).fill(Color(NSColor.quaternaryLabelColor))
                VStack(spacing: 0) {
                  Color.blue.frame(height: g.size.height * core.user)
                  Color.red.frame(height: g.size.height * core.system)
                }.clipShape(RoundedRectangle(cornerRadius: 3))
              }
            }.frame(height: 36)
            Text("\(i+1)").font(.system(size: 8)).foregroundColor(.secondary)
          }
        }
      }.padding(.top, 3)
    case .memory:
      item("Wired", bytes(s.wired), .pink)
      item("Active", bytes(s.active), .green)
      item("Compressed", bytes(s.compressed), .purple)
      item("Available & cached", bytes(max(0, s.memoryTotal - s.memoryUsed)))
      item("Swap", bytes(s.swap))
      item("Memory pressure", s.pressureText)
    case .network:
      item("Upload · Tx", rate(s.upload, bits: settings.value.networkBits), .green)
      item("Download · Rx", rate(s.download, bits: settings.value.networkBits), .red)
      item("Interface", s.interface.isEmpty ? "Disconnected" : s.interface)
    case .disk:
      item("Read", s.diskAvailable ? rate(s.diskRead) : "Unavailable", .green)
      item("Write", s.diskAvailable ? rate(s.diskWrite) : "Unavailable", .red)
      item("Scope", "Physical storage")
    case .temperature:
      item("Sensor", s.temperatureName)
      ForEach(s.sensors.filter { $0.name.contains("ACC") }.prefix(5)) { sensor in
        item(sensor.name, temperatureText(sensor.celsius, fahrenheit: settings.value.fahrenheit))
      }
      if s.temperature == nil {
        Text("The selected sensor is unavailable.").font(.system(size: 11)).foregroundColor(
          .secondary)
      }
    case .battery:
      if let battery = s.battery {
        BatteryDetailsView(reading: battery, compact: true)
      } else {
        Text("No internal battery detected.").font(.system(size: 11))
      }
    case .input, .consumption:
      item("Charger input", watts(s.inputWatts), .meterMint)
      item("Mac consumption", watts(s.systemWatts), .orange)
      item("Charger capacity", watts(s.adapterWatts))
      item("Power source", s.externalPower ? "Charger" : "Battery")
      item("Battery", s.batteryPercent.map { String(format: "%.0f%%", $0) } ?? "Unavailable")
      item("Energy this session", String(format: "%.3f Wh", s.sessionWh))
      Text("Live hardware telemetry. Charger capacity is the rated maximum; energy excludes sleep.")
        .font(.system(size: 10)).foregroundColor(.secondary).lineSpacing(2).fixedSize(
          horizontal: false, vertical: true)
    }
  }
  private func item(_ label: String, _ value: String, _ color: Color = .primary) -> some View {
    HStack {
      Text(label).foregroundColor(.secondary)
      Spacer()
      Text(value).monospacedDigit().foregroundColor(color)
    }.font(.system(size: 11))
  }
}

// Keep the viewport inside the usable display; overflow remains scrollable.
struct PopoverLayout {
  static func size(ideal: NSSize, available: NSSize) -> NSSize {
    NSSize(
      width: min(ideal.width, max(1, available.width - 16)),
      height: min(ceil(ideal.height), max(1, available.height - 28)))
  }
}
