import AppKit
import Combine
import IOKit
import IOKit.pwr_mgt
import SwiftUI

enum SleepControlError: Error, LocalizedError {
  case cancelled
  case failed(String)
  var errorDescription: String? {
    switch self {
    case .cancelled: "Authorization was cancelled."
    case .failed(let message): message
    }
  }
}

protocol SleepBackend {
  var supportsClosedLid: Bool { get }
  func beginStayAwake() throws -> IOPMAssertionID
  func endStayAwake(_ assertion: IOPMAssertionID) throws
  func readSleepDisabled() -> Bool?
  func setSleepDisabled(
    _ disabled: Bool, completion: @escaping (Result<Void, SleepControlError>) -> Void)
}

final class MacSleepBackend: SleepBackend {
  var supportsClosedLid: Bool {
    let service = IOServiceGetMatchingService(
      0, IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return false }
    IOObjectRelease(service)
    return true
  }

  func beginStayAwake() throws -> IOPMAssertionID {
    var assertion: IOPMAssertionID = 0
    let result = IOPMAssertionCreateWithName(
      kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      "Mica · Stay awake" as CFString, &assertion)
    guard result == kIOReturnSuccess else {
      throw SleepControlError.failed("macOS could not enable Stay awake (\(result)).")
    }
    return assertion
  }

  func endStayAwake(_ assertion: IOPMAssertionID) throws {
    let result = IOPMAssertionRelease(assertion)
    guard result == kIOReturnSuccess else {
      throw SleepControlError.failed("macOS could not release Stay awake (\(result)).")
    }
  }

  func readSleepDisabled() -> Bool? {
    let root = IOServiceGetMatchingService(0, IOServiceMatching("IOPMrootDomain"))
    guard root != 0 else { return nil }
    defer { IOObjectRelease(root) }
    guard
      let property = IORegistryEntryCreateCFProperty(
        root, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    else { return nil }
    return (property as? NSNumber)?.boolValue
  }

  // Only these two fixed commands can reach the authorization prompt. No password
  // is collected, saved, or passed through this app, and no helper is installed.
  static func authorizationScript(disabled: Bool) -> String {
    """
    do shell script "/usr/bin/pmset -a disablesleep \(disabled ? "1" : "0")" with prompt "Mica needs permission to change system sleep, including sleep when the lid is closed." with administrator privileges
    """
  }

  func setSleepDisabled(
    _ disabled: Bool, completion: @escaping (Result<Void, SleepControlError>) -> Void
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      process.arguments = ["-e", Self.authorizationScript(disabled: disabled)]
      let output = Pipe()
      process.standardOutput = output
      process.standardError = output
      let result: Result<Void, SleepControlError>
      do {
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let message = String(decoding: data, as: UTF8.self).trimmingCharacters(
          in: .whitespacesAndNewlines)
        if process.terminationStatus == 0 {
          result = .success(())
        } else if message.contains("-128") {
          result = .failure(.cancelled)
        } else {
          result = .failure(
            .failed(message.isEmpty ? "macOS could not change lid-closed sleep." : message))
        }
      } catch {
        result = .failure(.failed(error.localizedDescription))
      }
      DispatchQueue.main.async { completion(result) }
    }
  }
}

final class SleepController: ObservableObject {
  @Published private(set) var stayAwake = false
  @Published private(set) var lidSleepDisabled: Bool?
  @Published private(set) var changingLidSleep = false
  @Published private(set) var errorMessage: String?
  @Published private(set) var sessionDeadline: Date?
  @Published private(set) var sessionMessage: String?
  let supportsClosedLid: Bool
  private let backend: SleepBackend
  private let clock: () -> Date
  private let observe: Bool
  private var assertion: IOPMAssertionID?
  private var deadlineTimer: Timer?
  private var wakeObserver: NSObjectProtocol?

  init(backend: SleepBackend = MacSleepBackend(), observe: Bool = true, now: @escaping () -> Date = Date.init) {
    self.backend = backend
    self.observe = observe
    self.clock = now
    supportsClosedLid = backend.supportsClosedLid
    refresh()
    if observe {
      wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.checkSession(); self?.refresh() }
    }
  }
  deinit {
    deadlineTimer?.invalidate()
    if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    if let assertion { try? backend.endStayAwake(assertion) }
  }
  func refresh() {
    guard !changingLidSleep else { return }
    lidSleepDisabled = backend.readSleepDisabled()
  }
  func setStayAwake(_ enabled: Bool) {
    errorMessage = nil
    do {
      if enabled {
        if assertion == nil { assertion = try backend.beginStayAwake() }
      } else if let assertion {
        try backend.endStayAwake(assertion)
        self.assertion = nil
      }
      stayAwake = enabled
      sessionDeadline = nil; sessionMessage = nil
      deadlineTimer?.invalidate(); deadlineTimer = nil
    } catch { errorMessage = error.localizedDescription }
  }
  func startSession(minutes: Int) {
    guard (1...1440).contains(minutes) else {
      errorMessage = "Choose a duration between 1 and 1440 minutes."
      return
    }
    startSession(until: clock().addingTimeInterval(Double(minutes) * 60))
  }
  func startSession(until date: Date) {
    let duration = date.timeIntervalSince(clock())
    guard duration.isFinite, duration > 0, duration <= 86400 else {
      errorMessage = "Choose a future end time within 24 hours."
      return
    }
    errorMessage = nil
    do {
      if assertion == nil { assertion = try backend.beginStayAwake() }
      stayAwake = true; sessionDeadline = date; sessionMessage = nil
      scheduleDeadline()
    } catch { errorMessage = error.localizedDescription }
  }
  func checkSession() {
    guard stayAwake, let sessionDeadline else { return }
    if clock() >= sessionDeadline { endSession(reason: "Timed session ended.") }
    else { scheduleDeadline() }
  }
  private func scheduleDeadline() {
    deadlineTimer?.invalidate(); deadlineTimer = nil
    guard observe, stayAwake, let sessionDeadline else { return }
    let remaining = max(0.01, sessionDeadline.timeIntervalSince(clock()))
    let timer = Timer(timeInterval: remaining, repeats: false) { [weak self] _ in
      self?.deadlineTimer = nil
      self?.checkSession()
    }
    timer.tolerance = min(1, remaining * 0.01)
    RunLoop.main.add(timer, forMode: .common)
    deadlineTimer = timer
  }
  func enforceBatteryLimit(_ battery: BatteryReading?, threshold: Double) {
    guard stayAwake, (1...50).contains(threshold), battery?.externalPower == false,
      let charge = battery?.chargePercent, charge.isFinite, (0...100).contains(charge), charge <= threshold
    else { return }
    endSession(reason: String(format: "Session ended at %.0f%% battery.", charge))
  }
  private func endSession(reason: String) {
    setStayAwake(false)
    if !stayAwake { sessionMessage = reason }
  }
  func setLidSleepDisabled(_ disabled: Bool) {
    guard !changingLidSleep else { return }
    refresh()
    guard supportsClosedLid else {
      errorMessage = "Lid-closed sleep is only available on a Mac notebook."
      return
    }
    guard let current = lidSleepDisabled else {
      errorMessage = "The current system sleep setting could not be read. Try again."
      return
    }
    guard disabled != current else { return }
    errorMessage = nil
    changingLidSleep = true
    backend.setSleepDisabled(disabled) { [weak self] result in
      guard let self else { return }
      self.changingLidSleep = false
      self.refresh()
      switch result {
      case .success:
        if self.lidSleepDisabled != disabled {
          self.errorMessage = "macOS did not confirm the new sleep setting. The toggle shows the current system state."
        }
      case .failure(.cancelled): break
      case .failure(let error): self.errorMessage = error.localizedDescription
      }
    }
  }
  func stop() {
    deadlineTimer?.invalidate(); deadlineTimer = nil
    setStayAwake(false)
  }
}

struct SleepControlsView: View {
  @ObservedObject var sleep: SleepController
  @ObservedObject var settings: Settings
  @ViewState private var sessionMode = 0
  @ViewState private var endTime = Date().addingTimeInterval(3600)
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Sleep controls", systemImage: "moon.zzz").font(.system(size: 13, weight: .semibold))
      control(
        "Stay awake",
        detail: "Prevents idle system sleep. The display can still turn off.",
        binding: Binding(get: { sleep.stayAwake }, set: { sleep.setStayAwake($0) }))
      if sleep.stayAwake {
        if let end = sleep.sessionDeadline {
          Text("Ends " + DateFormatter.localizedString(from: end, dateStyle: .short, timeStyle: .short))
            .font(.system(size: 11)).monospacedDigit()
        } else {
          Text("Active until stopped or Mica quits.").font(.system(size: 11))
        }
      } else if let message = sleep.sessionMessage {
        Text(message).font(.system(size: 11)).foregroundColor(.secondary)
      }
      Divider()
      Picker("Timed session", selection: $sessionMode) {
        Text("Duration").tag(0); Text("End time").tag(1)
      }.pickerStyle(.segmented).frame(width: 260)
      if sessionMode == 0 {
        HStack {
          Picker("Duration preset", selection: $settings.value.wakeDurationMinutes) {
            Text("15 minutes").tag(15)
            Text("30 minutes").tag(30)
            Text("1 hour").tag(60)
            Text("2 hours").tag(120)
            if ![15, 30, 60, 120].contains(settings.value.wakeDurationMinutes) {
              Text("Custom").tag(settings.value.wakeDurationMinutes)
            }
          }.frame(width: 220)
          TextField("Minutes", value: $settings.value.wakeDurationMinutes, format: .number)
            .frame(width: 65).accessibilityLabel("Session minutes")
          Text("min").font(.system(size: 11))
          Stepper("Session minutes", value: $settings.value.wakeDurationMinutes, in: 1...1440)
            .labelsHidden().accessibilityLabel("Adjust session minutes")
        }
      } else {
        DatePicker("End session at", selection: $endTime, displayedComponents: [.date, .hourAndMinute])
      }
      HStack {
        Button("Start timed session") {
          if sessionMode == 0 { sleep.startSession(minutes: settings.value.wakeDurationMinutes) }
          else { sleep.startSession(until: endTime) }
        }
        if sleep.stayAwake { Button("End session") { sleep.setStayAwake(false) } }
      }.controlSize(.small)
      Toggle("End session on low battery", isOn: Binding(
        get: { settings.value.wakeBatteryFloor > 0 },
        set: { settings.value.wakeBatteryFloor = $0 ? 20 : 0 }))
        .font(.system(size: 11)).toggleStyle(.switch)
      if settings.value.wakeBatteryFloor > 0 {
        Stepper("Stop at \(String(format: "%.0f", settings.value.wakeBatteryFloor))% while on battery",
          value: $settings.value.wakeBatteryFloor, in: 1...50)
          .font(.system(size: 11)).accessibilityLabel("Session battery cutoff")
        Text("Uses live battery readings while monitoring is running.")
          .font(.system(size: 10)).foregroundColor(.secondary)
      }
      Divider()
      control(
        "No sleep when lid closed",
        detail: sleep.supportsClosedLid
          ? "Disables system sleep, including lid-close. Requires administrator approval; stays on until switched off."
          : "Available on Mac notebooks.",
        binding: Binding(
          get: { sleep.lidSleepDisabled == true }, set: { sleep.setLidSleepDisabled($0) })
      )
      .disabled(!sleep.supportsClosedLid || sleep.changingLidSleep || sleep.lidSleepDisabled == nil)
      if sleep.changingLidSleep {
        HStack(spacing: 7) {
          ProgressView().controlSize(.small)
          Text("Waiting for macOS authorization…").font(.system(size: 11)).foregroundColor(
            .secondary)
        }
      }
      if let message = sleep.errorMessage {
        Text(message).font(.system(size: 11)).foregroundColor(.red).fixedSize(
          horizontal: false, vertical: true)
      } else if sleep.supportsClosedLid && sleep.lidSleepDisabled == nil {
        Text("System sleep state is unavailable.").font(.system(size: 11)).foregroundColor(
          .secondary)
      }
      if sleep.lidSleepDisabled == true {
        Text(
          "Turn this off before carrying your Mac in a bag. It remains enabled even after quitting Mica."
        )
        .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(
          horizontal: false, vertical: true)
      }
    }.onAppear { sleep.refresh(); sleep.checkSession() }
  }
  private func control(_ title: String, detail: String, binding: Binding<Bool>) -> some View {
    HStack(spacing: 18) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.system(size: 12, weight: .medium))
        Text(detail).font(.system(size: 10)).foregroundColor(.secondary).fixedSize(
          horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Toggle(title, isOn: binding).labelsHidden().toggleStyle(.switch).controlSize(.small)
    }
  }
}
