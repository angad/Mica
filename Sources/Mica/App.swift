import AppKit
import Combine
import Hardware
import ScreenCaptureKit
import SwiftUI

@main
struct MicaMain {
  static func main() {
    if CommandLine.arguments.contains("--diagnose-processes") {
      let before = ProcessReader.read()
      Thread.sleep(forTimeInterval: 1)
      let after = ProcessReader.read()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      if let data = try? encoder.encode(ProcessReader.readings(after, previous: before)) {
        print(String(decoding: data, as: UTF8.self))
      }
      return
    }
    if CommandLine.arguments.contains("--check-timed-awake") {
      let backend = MacSleepBackend()
      let before = backend.readSleepDisabled()
      let controller = SleepController(backend: backend)
      controller.startSession(until: Date().addingTimeInterval(2))
      guard controller.stayAwake else { fputs("Could not create timed assertion\n", stderr); exit(1) }
      let limit = Date().addingTimeInterval(5)
      while controller.stayAwake && Date() < limit {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
      }
      guard !controller.stayAwake, backend.readSleepDisabled() == before else {
        controller.stop()
        fputs("Timed assertion did not expire cleanly\n", stderr); exit(1)
      }
      print("Timed assertion expired and released. Persistent sleep state unchanged.")
      return
    }
    if CommandLine.arguments.contains("--check-awake") {
      let backend = MacSleepBackend()
      do {
        let before = backend.readSleepDisabled()
        let assertion = try backend.beginStayAwake()
        print("Stay-awake assertion created: \(assertion)")
        Thread.sleep(forTimeInterval: 2)
        try backend.endStayAwake(assertion)
        print(
          "Stay-awake assertion released. Lid state unchanged: \(before == backend.readSleepDisabled())"
        )
      } catch {
        fputs("\(error)\n", stderr)
        exit(1)
      }
      return
    }
    if CommandLine.arguments.contains("--diagnose") {
      let settings = Settings(
        defaults: UserDefaults(suiteName: "sg.angad.Mica.diagnostics")!)
      let monitor = Monitor(settings: settings, start: false)
      var sample = GMSample()
      gm_sample(&sample)
      monitor.accept(
        sample, time: ProcessInfo.processInfo.systemUptime, battery: MacBatteryReader.read())
      Thread.sleep(forTimeInterval: 1)
      gm_sample(&sample)
      monitor.accept(
        sample, time: ProcessInfo.processInfo.systemUptime, battery: MacBatteryReader.read())
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      if let data = try? encoder.encode(monitor.snapshot) {
        print(String(decoding: data, as: UTF8.self))
      }
      return
    }
    if CommandLine.arguments.contains("--version") {
      print(AppVersion.current)
      return
    }
    if CommandLine.arguments.contains("--diagnose-devices") {
      do {
        let readings = try MobileBatteryScanner().scan().compactMap(\.reading)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        print(String(decoding: try encoder.encode(readings), as: UTF8.self))
      } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
      }
      return
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
  }
}
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
  let settings = Settings(
    defaults: CommandLine.arguments.contains("--check-clicks")
      ? UserDefaults(suiteName: "sg.angad.Mica.interactionchecks")! : .standard)
  let sleep = SleepController()
  lazy var monitor = Monitor(settings: settings)
  private var status: NSStatusItem!
  private let meterBar = MeterBarView()
  private var window: NSWindow?
  private let popover = NSPopover()
  private var selectedMeter: Meter?
  private var lastPane: Pane = {
    let args = CommandLine.arguments
    if args.contains("--battery-settings") { return .battery }
    if args.contains("--devices-settings") { return .devices }
    if args.contains("--sleep-settings") { return .general }
    if args.contains("--alerts-settings") { return .alerts }
    return .cpu
  }()
  private var subscriptions = Set<AnyCancellable>()
  func applicationDidFinishLaunching(_ notification: Notification) {
    let others = NSRunningApplication.runningApplications(
      withBundleIdentifier: Bundle.main.bundleIdentifier ?? "sg.angad.Mica"
    ).filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if !others.isEmpty && !CommandLine.arguments.contains("--render")
      && !CommandLine.arguments.contains("--check-clicks")
    {
      if CommandLine.arguments.contains("--replace") {
        others.forEach { $0.terminate() }
      } else {
        others.first?.activate()
        NSApp.terminate(nil)
        return
      }
    }
    sleep.$errorMessage.compactMap { $0 }.sink { [weak self] message in
      guard self?.window?.isVisible != true else { return }
      DispatchQueue.main.async {
        let alert = NSAlert()
        alert.messageText = "Sleep setting could not be changed"
        alert.informativeText = message
        alert.runModal()
      }
    }.store(in: &subscriptions)
    installMenu()
    status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    status.autosaveName = "Mica"
    if let button = status.button {
      button.target = self
      button.action = #selector(showSettings)
      meterBar.frame = button.bounds
      meterBar.autoresizingMask = [.width, .height]
      meterBar.onSelect = { [weak self] meter in self?.activateMeter(meter) }
      meterBar.onContextMenu = { [weak self] event, view in
        guard let self else { return }
        NSMenu.popUpContextMenu(self.statusMenu(), with: event, for: view)
      }
      button.addSubview(meterBar)
    }
    popover.behavior = .transient
    popover.delegate = self
    popover.animates = true
    monitor.$snapshot.sink { [weak self] _ in DispatchQueue.main.async { self?.updateMeter() } }
      .store(in: &subscriptions)
    settings.$value.sink { [weak self] _ in
      DispatchQueue.main.async {
        self?.applyAppearance()
        self?.updateMeter()
      }
    }.store(in: &subscriptions)
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(updateMeter),
      name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
    applyAppearance()
    updateMeter()
    monitor.onSample = { [weak self] snapshot in
      guard let self else { return }
      self.sleep.enforceBatteryLimit(snapshot.battery, threshold: self.settings.value.wakeBatteryFloor)
    }
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.monitor.alerts.resetPending() }
    if CommandLine.arguments.contains("--check-clicks") {
      settings.value = Preferences()
      settings.value.enabled = Set(Meter.allCases)
      popover.animates = false
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.checkComponentActions() }
      return
    }
    if !UserDefaults.standard.bool(forKey: "hasLaunched")
      || CommandLine.arguments.contains("--settings") || CommandLine.arguments.contains("--render")
      || CommandLine.arguments.contains("--battery-settings")
      || CommandLine.arguments.contains("--devices-settings")
      || CommandLine.arguments.contains("--sleep-settings")
      || CommandLine.arguments.contains("--alerts-settings")
    {
      showSettings()
      UserDefaults.standard.set(true, forKey: "hasLaunched")
    }
    if let index = CommandLine.arguments.firstIndex(of: "--render"),
      CommandLine.arguments.count > index + 1
    {
      let directory = CommandLine.arguments[index + 1]
      DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        if #available(macOS 14.4, *) {
          self.render(to: directory)
        } else {
          print("UI capture requires macOS 14.4 or later.")
          NSApp.terminate(nil)
        }
      }
    }
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showSettings()
    return true
  }
  private func installMenu() {
    let main = NSMenu()
    let appItem = NSMenuItem()
    main.addItem(appItem)
    let menu = NSMenu()
    let prefs = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
    prefs.target = self
    menu.addItem(prefs)
    menu.addItem(.separator())
    menu.addItem(
      NSMenuItem(
        title: "Quit Mica", action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"))
    appItem.submenu = menu
    NSApp.mainMenu = main
    let edit = NSMenuItem()
    edit.title = "Edit"
    let editMenu = NSMenu(title: "Edit")
    for (title, selector, key) in [
      ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"),
      ("Select All", #selector(NSText.selectAll(_:)), "a"),
    ] { editMenu.addItem(NSMenuItem(title: title, action: selector, keyEquivalent: key)) }
    edit.submenu = editMenu
    main.addItem(edit)
  }
  private func applyAppearance() {
    NSApp.appearance =
      settings.value.appearance == "Dark"
      ? NSAppearance(named: .darkAqua)
      : settings.value.appearance == "Light" ? NSAppearance(named: .aqua) : nil
  }
  @objc func updateMeter() {
    guard status != nil else { return }
    let s = monitor.snapshot
    let dark = status.button?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    let image = MeterPainter.image(s, settings.value, dark: dark)
    if status.length != image.size.width + 2 { status.length = image.size.width + 2 }
    meterBar.update(image: image, regions: MeterPainter.regions(s, settings.value))
    let summary =
      "Mica. CPU \(Int(s.cpu*100)) percent. Memory \(bytes(s.memoryUsed)). Temperature \(temperatureText(s.temperature,fahrenheit:settings.value.fahrenheit)). Charger \(watts(s.inputWatts)). Mac \(watts(s.systemWatts))."
    status.button?.toolTip = summary + " Click for details. Right-click for settings."
    status.button?.setAccessibilityLabel(summary)
  }
  private func statusMenu() -> NSMenu {
    let menu = NSMenu()
    let settingsItem = NSMenuItem(
      title: "Mica Settings…", action: #selector(showSettings), keyEquivalent: ",")
    settingsItem.target = self
    menu.addItem(settingsItem)
    let pause = NSMenuItem(
      title: monitor.paused ? "Resume meters" : "Pause meters", action: #selector(togglePause),
      keyEquivalent: "")
    pause.target = self
    menu.addItem(pause)
    menu.addItem(.separator())
    sleep.refresh()
    let awakeItem = NSMenuItem(
      title: "Stay awake", action: #selector(toggleStayAwake), keyEquivalent: "")
    awakeItem.target = self
    awakeItem.state = sleep.stayAwake ? .on : .off
    awakeItem.toolTip = "Prevents idle sleep until Mica quits."
    if let end = sleep.sessionDeadline {
      awakeItem.title = "Stay awake until " + DateFormatter.localizedString(from: end, dateStyle: .none, timeStyle: .short)
    }
    menu.addItem(awakeItem)
    let timed = NSMenuItem(title: "Timed stay awake", action: nil, keyEquivalent: "")
    let durations = NSMenu()
    for minutes in [15, 30, 60, 120] {
      let item = NSMenuItem(title: "\(minutes) minutes", action: #selector(startTimedStayAwake(_:)), keyEquivalent: "")
      item.target = self; item.tag = minutes
      durations.addItem(item)
    }
    timed.submenu = durations
    menu.addItem(timed)
    let lidItem = NSMenuItem(
      title: "No sleep when lid closed…", action: #selector(toggleLidSleep), keyEquivalent: "")
    lidItem.target = self
    lidItem.state = sleep.lidSleepDisabled == true ? .on : .off
    lidItem.isEnabled =
      sleep.supportsClosedLid && sleep.lidSleepDisabled != nil && !sleep.changingLidSleep
    lidItem.toolTip =
      "Administrator approval required. Disables system sleep until switched off, including after quitting."
    menu.addItem(lidItem)
    menu.autoenablesItems = false
    menu.addItem(.separator())
    menu.addItem(
      NSMenuItem(
        title: "Quit Mica", action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"))
    return menu
  }
  private func activateMeter(_ meter: Meter) {
    if popover.isShown && selectedMeter == meter {
      popover.performClose(nil)
      return
    }
    showPopover(for: meter)
  }
  // Exercise the actual status-item hierarchy and native target/action dispatch,
  // without synthesizing mouse events or interacting with another application.
  private func checkComponentActions() {
    Task { @MainActor in
      updateMeter()
      meterBar.layoutSubtreeIfNeeded()
      guard let statusButton = status.button else { exit(1) }
      for meter in Meter.allCases where settings.value.enabled.contains(meter) {
        guard let component = meterBar.buttons[meter] else { exit(1) }
        let location = component.convert(
          NSPoint(x: component.bounds.midX, y: component.bounds.midY), to: statusButton.superview)
        guard let hit = statusButton.hitTest(location) as? MeterComponentButton, hit.meter == meter
        else {
          fputs("Wrong native hit target for \(meter.title)\n", stderr)
          exit(1)
        }
        hit.performClick(nil)
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard selectedMeter == meter, popover.isShown else {
          fputs("Missing popup for \(meter.title)\n", stderr)
          exit(1)
        }
        print("\(meter.title): native button hit and matching popup opened")
      }
      if let selectedMeter { meterBar.buttons[selectedMeter]?.performClick(nil) }
      guard !popover.isShown else { exit(1) }
      print("Repeat click closes the active popup. All visible component actions passed.")
      NSApp.terminate(nil)
    }
  }
  private func showPopover(for meter: Meter, heightLimit: CGFloat? = nil) {
    guard let button = status.button else { return }
    popover.close()
    selectedMeter = meter
    monitor.showDetailedSensors(meter == .temperature, viewer: "popover")
    let screen = button.window?.screen ?? NSScreen.main
    var available = screen?.visibleFrame.size ?? NSSize(width: 800, height: 600)
    if let heightLimit { available.height = min(available.height, heightLimit) }
    let width = min(320, max(1, available.width - 16))
    let content = PopoverView(
      settings: settings, monitor: monitor, meter: meter,
      openSettings: { [weak self] in self?.showSettings() }, width: width)
    let sizingView = NSHostingView(rootView: content)
    let ideal = sizingView.fittingSize
    let size = PopoverLayout.size(
      ideal: NSSize(width: width, height: ideal.height), available: available)
    let host = NSHostingController(
      rootView:
        ScrollView(.vertical) { content }
        .frame(width: size.width, height: size.height)
        .background(Color(NSColor.windowBackgroundColor)))
    if #available(macOS 13, *) { host.sizingOptions = [] }
    host.view.setFrameSize(size)
    popover.contentViewController = host
    popover.contentSize = size
    meterBar.layoutSubtreeIfNeeded()
    let anchor = meterBar.buttons[meter] ?? button
    popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
  }
  func applicationWillTerminate(_ notification: Notification) { sleep.stop() }
  func popoverDidClose(_ notification: Notification) {
    guard !popover.isShown else { return }
    popover.contentViewController = nil
    monitor.showDetailedSensors(false, viewer: "popover")
    monitor.processes.setVisible(false, viewer: "popover-cpu")
    monitor.processes.setVisible(false, viewer: "popover-memory")
  }
  func windowWillClose(_ notification: Notification) {
    // Closed hosting views otherwise continue observing each sample and laying out.
    window?.contentView = nil
    window = nil
    monitor.showDetailedSensors(false, viewer: "settings")
    monitor.processes.setVisible(false, viewer: "settings-cpu")
    monitor.processes.setVisible(false, viewer: "settings-memory")
  }
  @objc private func toggleStayAwake() { sleep.setStayAwake(!sleep.stayAwake) }
  @objc private func startTimedStayAwake(_ sender: NSMenuItem) { sleep.startSession(minutes: sender.tag) }
  @objc private func toggleLidSleep() { sleep.setLidSleepDisabled(sleep.lidSleepDisabled != true) }
  @objc private func togglePause() { monitor.togglePause() }
  @objc func showSettings() {
    popover.performClose(nil)
    if window == nil {
      let w = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 720, height: 720),
        styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered,
        defer: false)
      w.title = "Mica Settings"
      w.titleVisibility = .hidden
      w.titlebarAppearsTransparent = true
      w.toolbarStyle = .unifiedCompact
      w.isReleasedWhenClosed = false
      let container = NSHostingView(
        rootView: SettingsView(
          settings: settings, monitor: monitor, sleep: sleep,
          pane: lastPane,
          onPaneChanged: { [weak self] in self?.lastPane = $0 }))
      w.contentView = container
      w.setContentSize(NSSize(width: 720, height: 720))
      w.center()
      w.delegate = self
      window = w
    }
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  @available(macOS 14.4, *)
  private func renderPopover(to directory: String, index: Int = 0) {
    window?.orderOut(nil)
    let sequence: [Meter] = [
      .network, .temperature, .disk, .memory, .cpu, .input, .consumption, .consumption,
    ]
    guard index < sequence.count else {
      NSApp.terminate(nil)
      return
    }
    let meter = sequence[index]
    let smallScreen = index == sequence.count - 1
    showPopover(for: meter, heightLimit: smallScreen ? 280 : nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
      Task { @MainActor in
        do {
          let content = try await SCShareableContent.currentProcess
          if let number = self.popover.contentViewController?.view.window?.windowNumber,
            let ownWindow = content.windows.first(where: { $0.windowID == CGWindowID(number) })
          {
            let config = SCStreamConfiguration()
            config.width = Int(ownWindow.frame.width * 2)
            config.height = Int(ownWindow.frame.height * 2)
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            let image = try await SCScreenshotManager.captureImage(
              contentFilter: SCContentFilter(desktopIndependentWindow: ownWindow),
              configuration: config)
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
              .write(
                to: URL(
                  fileURLWithPath: directory + "/" + meter.rawValue + (smallScreen ? "-short" : "")
                    + "-popover.png"))
          }
        } catch { print("Popover render failed: \(error)") }
        self.renderPopover(to: directory, index: index + 1)
      }
    }
  }
  @available(macOS 14.4, *)
  private func render(to directory: String, index: Int = 0) {
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let panes = Pane.allCases
    guard index < panes.count * 2 else {
      renderPopover(to: directory)
      return
    }
    let dark = index >= panes.count
    let pane = panes[index % panes.count]
    window?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window?.contentView = NSHostingView(
      rootView: SettingsView(settings: settings, monitor: monitor, sleep: sleep, pane: pane))
    window?.setContentSize(NSSize(width: 720, height: 720))
    window?.contentView?.layoutSubtreeIfNeeded()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
      Task { @MainActor in
        do {
          // Capture only this application's own window. This API requires
          // no Screen Recording permission and cannot see other apps.
          let content = try await SCShareableContent.currentProcess
          guard
            let ownWindow = content.windows.first(where: {
              $0.windowID == CGWindowID(self.window!.windowNumber)
            })
          else { throw NSError(domain: "Mica.Render", code: 1) }
          let filter = SCContentFilter(desktopIndependentWindow: ownWindow)
          let config = SCStreamConfiguration()
          config.width = Int(ownWindow.frame.width * 2)
          config.height = Int(ownWindow.frame.height * 2)
          config.showsCursor = false
          config.ignoreShadowsSingleWindow = true
          let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config)
          let rep = NSBitmapImageRep(cgImage: image)
          let name = pane.rawValue.lowercased() + (dark ? "-dark" : "-light") + ".png"
          try rep.representation(using: .png, properties: [:])!.write(
            to: URL(fileURLWithPath: directory + "/" + name))
        } catch { print("Render failed: \(error)") }
        if index == 0 {
          let image = MeterPainter.image(self.monitor.snapshot, self.settings.value, dark: true)
          if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(
              to: URL(fileURLWithPath: directory + "/menubar.png"))
          }
        }
        self.render(to: directory, index: index + 1)
      }
    }
  }
}
