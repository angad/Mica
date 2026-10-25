import AppKit
import ServiceManagement
import SwiftUI

// Qualify the property-wrapper type to avoid the SDK 27 State macro, which
// is not shipped with standalone Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>

struct SettingsView: View {
  @ObservedObject var settings: Settings
  @ObservedObject var monitor: Monitor
  @ObservedObject var sleep: SleepController
  @ViewState var pane: Pane = .cpu
  @ViewState private var loginError: String?
  @ViewState private var loginEnabled = LoginStartup.enabled
  @Environment(\.colorScheme) private var scheme
  private var s: Snapshot { monitor.snapshot }
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 9) {
        Image(systemName: "chart.bar.xaxis").font(.system(size: 24, weight: .semibold))
          .foregroundColor(.blue).frame(width: 36, height: 36).meterGlass(
            tint: .blue.opacity(0.12), radius: 13)
        VStack(alignment: .leading, spacing: 3) {
          Text("Mica").font(.system(size: 21, weight: .semibold))
          Text("Your Mac, at a glance.").font(.system(size: 12)).foregroundColor(.secondary)
        }
        Spacer()
        HStack(spacing: 5) {
          Circle().fill(monitor.paused ? .orange : .green).frame(width: 6, height: 6)
          Text(
            monitor.paused ? "Paused" : "Live · \(String(format: "%g", settings.value.interval))s"
          ).font(
            .system(size: 11, weight: .medium)
          ).foregroundColor(.secondary)
        }.padding(.horizontal, 11).padding(.vertical, 7).meterGlass()
      }.padding(.horizontal, 26).padding(.top, 8).padding(.bottom, 14)
      HStack(spacing: 5) {
        ForEach(Pane.allCases) { item in
          Button {
            pane = item
          } label: {
            VStack(spacing: 6) {
              Image(systemName: item.symbol).font(.system(size: 19, weight: .regular)).frame(
                height: 23)
              Text(item.rawValue).font(
                .system(size: 11, weight: pane == item ? .semibold : .regular))
            }.frame(maxWidth: .infinity).frame(height: 51).foregroundColor(
              pane == item ? Color.accentColor : .secondary
            )
            .background(
              Group {
                if pane == item {
                  RoundedRectangle(cornerRadius: 14).fill(Color.blue.opacity(0.08)).meterGlass(
                    tint: .blue.opacity(0.05), radius: 14)
                }
              })
          }.buttonStyle(.plain).accessibilityLabel(item.rawValue + " settings")
            .accessibilityAddTraits(pane == item ? .isSelected : [])
        }
      }.padding(5).background(
        RoundedRectangle(cornerRadius: 19).fill(Color(NSColor.quaternaryLabelColor).opacity(0.35))
      )
      .padding(.horizontal, 24)
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text("MENU BAR PREVIEW").font(.system(size: 9, weight: .semibold)).tracking(1.2)
            .foregroundColor(.secondary)
          Spacer()
          Text("Memory → Network → Disk → Temp → CPU → Power").font(.system(size: 9))
            .foregroundColor(Color(NSColor.tertiaryLabelColor))
        }
        HStack {
          Spacer(minLength: 0)
          Image(nsImage: MeterPainter.image(s, settings.value, dark: scheme == .dark))
            .accessibilityLabel("Live menu bar preview")
          Spacer(minLength: 0)
        }.frame(height: 39).padding(.horizontal, 12).meterGlass(radius: 12).overlay(
          RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.07), lineWidth: 0.7))
      }.padding(.horizontal, 28).padding(.top, 14).padding(.bottom, 14)
      Divider().padding(.horizontal, 28)
      ScrollView {
        VStack(alignment: .leading, spacing: 15) {
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
              Text(
                pane == .general
                  ? "Make it yours" : pane == .power ? "Power & energy" : pane.rawValue
              ).font(.system(size: 23, weight: .semibold))
              Text(subtitle).font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer()
            if let meter = pane.meter {
              Toggle("Show in menu bar", isOn: settings.visible(meter)).toggleStyle(.switch)
                .controlSize(.small).font(.system(size: 11))
            }
          }
          content
        }.padding(.horizontal, 28).padding(.vertical, 18)
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
      Divider()
      HStack {
        Text("Mica \(AppVersion.current)").font(.system(size: 10)).foregroundColor(
          Color(NSColor.tertiaryLabelColor))
        Spacer()
        Button {
          NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
        } label: {
          Label("Activity Monitor", systemImage: "waveform.path.ecg")
        }
        .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(.secondary)
        Divider().frame(height: 12).padding(.horizontal, 7)
        Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.system(size: 11))
          .foregroundColor(.secondary)
      }.padding(.horizontal, 26).padding(.vertical, 15)
    }.frame(width: 720, height: 720).background(Color(NSColor.windowBackgroundColor))
  }
  private var subtitle: String {
    switch pane {
    case .cpu: "Per-core load, grouped above 32 cores. Blue for user, red for system."
    case .memory: "A stacked view of physical memory."
    case .disk: "Read and write activity across physical storage."
    case .network: "Upload and download, with the familiar Tx / Rx layout."
    case .temperature: "Live readings from your Mac’s thermal sensors."
    case .power: "See what comes in, what your Mac uses, and energy over time."
    case .battery: "Capacity, cycles and battery health over time."
    case .devices: "Battery diagnostics for paired iPhones and iPads."
    case .general: "The familiar meters, with a fresh coat of glass."
    }
  }
  @ViewBuilder private var content: some View {
    switch pane {
    case .cpu:
      HStack(spacing: 12) {
        stat("Total usage", String(format: "%.1f%%", s.cpu * 100), .blue)
        stat("CPU cores", "\(s.cores.count)", .secondary)
        stat(
          "System",
          String(
            format: "%.1f%%",
            s.cores.map(\.system).reduce(0, +) / Double(max(1, s.cores.count)) * 100), .red)
      }
      chart(.cpu)
      group {
        row("Display", detail: "Match your original per-core bars") {
          Picker("Display", selection: $settings.value.cpuPercent) {
            Text("Bars").tag(false)
            Text("Percentage").tag(true)
          }.labelsHidden().pickerStyle(.segmented).frame(width: 210)
        }
        Divider()
        row("Show each CPU core") {
          Toggle("Show each CPU core", isOn: $settings.value.cpuPerCore).labelsHidden().toggleStyle(
            .switch
          ).controlSize(.small).disabled(settings.value.cpuPercent)
        }
        Divider()
        row("Bar colors") {
          HStack(spacing: 18) {
            colorPicker("User", $settings.value.cpuUser)
            colorPicker("System", $settings.value.cpuSystem)
          }
        }
      }
    case .memory:
      HStack(spacing: 12) {
        stat("Used", bytes(s.memoryUsed), .purple)
        stat("Physical", bytes(s.memoryTotal), .secondary)
        stat("Pressure", s.pressureText, s.pressure == 1 || s.pressure == 0 ? .green : .orange)
      }
      group {
        row("Display") {
          Picker("Memory display", selection: $settings.value.memoryPercent) {
            Text("Stacked bar").tag(false)
            Text("Percentage").tag(true)
          }.labelsHidden().pickerStyle(.segmented).frame(width: 240)
        }
        Divider()
        memoryRow("Wired", s.wired, Color(NSColor(hex: "#A81D52")))
        memoryRow("Active", s.active, Color(NSColor(hex: "#97DE40")))
        memoryRow("Compressed", s.compressed, Color(NSColor(hex: "#935BFF")))
        memoryRow("Available & cached", max(0, s.memoryTotal - s.memoryUsed), .gray)
        Divider()
        row("Swap used") { Text(bytes(s.swap)).monospacedDigit().foregroundColor(.secondary) }
      }
    case .disk:
      HStack(spacing: 12) {
        stat("Read", s.diskAvailable ? rate(s.diskRead) : "Unavailable", .green)
        stat("Write", s.diskAvailable ? rate(s.diskWrite) : "Unavailable", .red)
      }
      chart(.disk)
      group {
        row("Display") {
          Picker("Disk display", selection: $settings.value.diskRates) {
            Text("Activity lights").tag(false)
            Text("Transfer rates").tag(true)
          }.labelsHidden().pickerStyle(.segmented).frame(width: 255)
        }
        Divider()
        row("Activity lights", detail: "Green flashes on reads; red flashes on writes.") {
          HStack(spacing: 7) {
            Circle().fill(.green).frame(width: 8, height: 8)
            Circle().fill(.red).frame(width: 8, height: 8)
          }
        }
      }
    case .network:
      HStack(spacing: 12) {
        stat("Upload · Tx", rate(s.upload, bits: settings.value.networkBits), .green)
        stat("Download · Rx", rate(s.download, bits: settings.value.networkBits), .red)
      }
      chart(.network)
      group {
        row(
          "Network interface",
          detail: "Currently reading \(s.interface.isEmpty ? "no active connection" : s.interface)"
        ) {
          Picker("Network interface", selection: $settings.value.networkInterface) {
            Text("Primary interface").tag("primary")
            ForEach(
              Array(
                Set(
                  s.interfaces
                    + (settings.value.networkInterface == "primary"
                      ? [] : [settings.value.networkInterface]))
              ).sorted(), id: \.self
            ) { Text($0).tag($0) }
          }.labelsHidden().frame(width: 210)
        }
        Divider()
        row("Units") {
          Picker("Network units", selection: $settings.value.networkBits) {
            Text("Bytes / sec").tag(false)
            Text("Bits / sec").tag(true)
          }.labelsHidden().pickerStyle(.segmented).frame(width: 240)
        }
        Divider()
        row("Rate colors") {
          HStack(spacing: 18) {
            colorPicker("Tx", $settings.value.transmit)
            colorPicker("Rx", $settings.value.receive)
          }
        }
      }
    case .temperature:
      HStack(spacing: 12) {
        stat(
          "\(s.temperatureName)",
          temperatureText(s.temperature, fahrenheit: settings.value.fahrenheit), .red)
        stat("Available sensors", "\(s.sensors.count)", .secondary)
      }
      chart(.temperature)
      group {
        row("Temperature sensor") {
          Picker("Temperature sensor", selection: $settings.value.temperatureSensor) {
            Text("Automatic").tag("Automatic")
            Text("CPU average").tag("CPU average")
            ForEach(s.sensors) { Text($0.name).tag($0.name) }
            if settings.value.temperatureSensor != "CPU average"
              && settings.value.temperatureSensor != "Automatic"
              && !s.sensors.contains(where: { $0.name == settings.value.temperatureSensor })
            {
              Text(settings.value.temperatureSensor + " (unavailable)").tag(
                settings.value.temperatureSensor)
            }
          }.labelsHidden().frame(width: 265)
        }
        Divider()
        row("Units") {
          Picker("Temperature units", selection: $settings.value.fahrenheit) {
            Text("Celsius · °C").tag(false)
            Text("Fahrenheit · °F").tag(true)
          }.labelsHidden().pickerStyle(.segmented).frame(width: 250)
        }
      }
      if s.temperature == nil {
        note(
          "This sensor is not available. Choose another sensor from the list.",
          symbol: "thermometer.medium")
      }
    case .power:
      HStack(spacing: 12) {
        stat("Charger input", watts(s.inputWatts), .meterMint)
        stat("Mac consumption", watts(s.systemWatts), .orange)
        stat("Session energy", String(format: "%.3f Wh", s.sessionWh), .secondary)
      }
      chart(.consumption)
      group {
        row("Charger input", detail: "Actual power arriving from your charger") {
          Toggle("Show charger input", isOn: settings.visible(.input)).labelsHidden().toggleStyle(
            .switch
          ).controlSize(.small)
        }
        Divider()
        row("Mac consumption", detail: "Current whole-system power draw") {
          Toggle("Show Mac consumption", isOn: settings.visible(.consumption)).labelsHidden()
            .toggleStyle(.switch).controlSize(.small)
        }
        Divider()
        row("Power source") {
          Text(
            s.externalPower
              ? (s.charging ? "Connected · charging" : "Connected · not charging") : "Battery"
          ).foregroundColor(.secondary)
        }
        Divider()
        row("Charger capacity", detail: "Rated capacity, separate from live input") {
          Text(watts(s.adapterWatts)).monospacedDigit().foregroundColor(.secondary)
        }
        Divider()
        row(
          "Energy this session",
          detail: String(format: "Charger input: %.3f Wh · excludes sleep", s.inputWh)
        ) { Button("Reset") { monitor.resetEnergy() }.controlSize(.small) }
      }
      note(
        "Watts measure the current rate of power use. Watt-hours measure energy accumulated while Mica is running.",
        symbol: "bolt.circle")
    case .battery:
      BatteryPanel(monitor: monitor, settings: settings, history: monitor.batteryHistory)
    case .devices:
      MobileBatteryPanel(
        mobile: monitor.mobile, settings: settings, history: monitor.batteryHistory)
    case .general:
      group { SleepControlsView(sleep: sleep) }
      group {
        row("Update interval", detail: "Applies to all meters") {
          Picker("Update interval", selection: $settings.value.interval) {
            Text("0.5 seconds").tag(0.5)
            Text("1 second").tag(1.0)
            Text("2 seconds").tag(2.0)
            Text("5 seconds").tag(5.0)
          }.labelsHidden().frame(width: 160)
        }
        Divider()
        row("Appearance") {
          Picker("Appearance", selection: $settings.value.appearance) {
            ForEach(["System", "Light", "Dark"], id: \.self) { Text($0).tag($0) }
          }.labelsHidden().pickerStyle(.segmented).frame(width: 240)
        }
        Divider()
        row("Extra compact spacing") {
          Toggle("Extra compact spacing", isOn: $settings.value.compact).labelsHidden().toggleStyle(
            .switch
          ).controlSize(.small)
        }
        Divider()
        row("Monochrome meters") {
          Toggle("Monochrome meters", isOn: $settings.value.monochrome).labelsHidden().toggleStyle(
            .switch
          ).controlSize(.small)
        }
        Divider()
        row("Open at login") {
          Toggle(
            "Open at login",
            isOn: Binding(
              get: { loginEnabled },
              set: { newValue in
                do {
                  try LoginStartup.setEnabled(newValue)
                  loginEnabled = LoginStartup.enabled
                  loginError = LoginStartup.approvalMessage
                } catch {
                  loginError = error.localizedDescription
                  loginEnabled = LoginStartup.enabled
                }
              })
          ).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
      }
      if let loginError { note(loginError, symbol: "info.circle") }
      HStack {
        Button(
          monitor.paused ? "Resume meters" : "Pause meters",
          systemImage: monitor.paused ? "play" : "pause"
        ) { monitor.togglePause() }
        Spacer()
        Button("Restore default layout") { settings.reset() }
      }.controlSize(.small)
      note(
        "Click a meter to see its live details. Right-click the menu bar meters to open settings or quit. Hold ⌘ and drag to reposition the whole group.",
        symbol: "cursorarrow.click")
    }
  }
  private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(title).font(.system(size: 10, weight: .medium)).foregroundColor(.secondary).lineLimit(1)
      Text(value).font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit()
        .foregroundColor(color).lineLimit(1).minimumScaleFactor(0.65)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(
      RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.quaternaryLabelColor).opacity(0.25)))
  }
  private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 11, content: content).padding(16).background(
      RoundedRectangle(cornerRadius: 15).fill(Color(NSColor.quaternaryLabelColor).opacity(0.25)))
  }
  private func row<Content: View>(
    _ title: String, detail: String? = nil, @ViewBuilder control: () -> Content
  ) -> some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.system(size: 12, weight: .medium))
        if let detail { Text(detail).font(.system(size: 10)).foregroundColor(.secondary) }
      }
      Spacer(minLength: 8)
      control().font(.system(size: 12))
    }.frame(minHeight: 24)
  }
  private func memoryRow(_ title: String, _ value: Double, _ color: Color) -> some View {
    HStack {
      Circle().fill(color).frame(width: 7, height: 7)
      Text(title).font(.system(size: 12))
      Spacer()
      Text(bytes(value)).font(.system(size: 12)).monospacedDigit().foregroundColor(.secondary)
    }
  }
  private func colorPicker(_ label: String, _ value: Binding<String>) -> some View {
    ColorPicker(
      label,
      selection: Binding(
        get: { Color(NSColor(hex: value.wrappedValue)) },
        set: { value.wrappedValue = NSColor($0).hex }), supportsOpacity: false
    ).font(.system(size: 11)).fixedSize()
  }
  private func note(_ text: String, symbol: String) -> some View {
    Label(text, systemImage: symbol).font(.system(size: 11)).foregroundColor(.secondary)
      .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
  }
  private func chart(_ meter: Meter) -> some View {
    HistoryChart(monitor: monitor, meter: meter).frame(height: 70).padding(12).background(
      RoundedRectangle(cornerRadius: 13).fill(Color(NSColor.quaternaryLabelColor).opacity(0.25)))
  }
}
struct HistoryChart: View {
  @ObservedObject var monitor: Monitor
  let meter: Meter
  private func values(_ p: HistoryPoint) -> [(String, Double)] {
    switch meter {
    case .cpu: [("CPU", p.cpu)]
    case .memory: [("Memory", p.memory)]
    case .battery: []
    case .temperature: p.temperature.map { [("Temperature", $0)] } ?? []
    case .network: [("Tx", p.upload), ("Rx", p.download)]
    case .disk: [("Read", p.read), ("Write", p.write)]
    case .input, .consumption:
      [("Input", p.input), ("Consumption", p.consumption)].compactMap { name, value in
        value.map { (name, $0) }
      }
    }
  }
  var body: some View {
    GeometryReader { geometry in
      let points = monitor.history
      let names = Array(Set(points.flatMap { values($0).map(\.0) })).sorted()
      let maximum = max(1, points.flatMap { values($0).map(\.1) }.max() ?? 1)
      ZStack {
        ForEach(Array(names.enumerated()), id: \.offset) { series, name in
          Path { path in
            var started = false
            for (index, point) in points.enumerated() {
              guard let value = values(point).first(where: { $0.0 == name })?.1 else {
                started = false
                continue
              }
              let location = CGPoint(
                x: geometry.size.width * Double(index) / Double(max(1, points.count - 1)),
                y: geometry.size.height * (1 - max(0, value) / maximum))
              if started {
                path.addLine(to: location)
              } else {
                path.move(to: location)
                started = true
              }
            }
          }.stroke(colors[min(series, colors.count - 1)], lineWidth: 1.8)
        }
      }
    }.accessibilityLabel(meter.title + " recent history")
  }
  private var colors: [Color] {
    switch meter {
    case .network, .disk: [.green, .red]
    case .input, .consumption: [.meterMint, .orange]
    default: [meter.color]
    }
  }
}
