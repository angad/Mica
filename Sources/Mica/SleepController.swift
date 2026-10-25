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
  let supportsClosedLid: Bool
  private let backend: SleepBackend
  private var assertion: IOPMAssertionID?
  private var timer: Timer?

  init(backend: SleepBackend = MacSleepBackend(), observe: Bool = true) {
    self.backend = backend
    supportsClosedLid = backend.supportsClosedLid
    refresh()
    if observe {
      timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
        self?.refresh()
      }
      timer?.tolerance = 1
    }
  }

  deinit {
    timer?.invalidate()
    if let assertion { try? backend.endStayAwake(assertion) }
  }

  func refresh() {
    guard !changingLidSleep else { return }
    lidSleepDisabled = backend.readSleepDisabled()
  }

  func setStayAwake(_ enabled: Bool) {
    guard enabled != stayAwake else { return }
    errorMessage = nil
    do {
      if enabled {
        assertion = try backend.beginStayAwake()
      } else if let assertion {
        try backend.endStayAwake(assertion)
        self.assertion = nil
      }
      stayAwake = enabled
    } catch { errorMessage = error.localizedDescription }
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
          self.errorMessage =
            "macOS did not confirm the new sleep setting. The toggle shows the current system state."
        }
      case .failure(.cancelled): break
      case .failure(let error): self.errorMessage = error.localizedDescription
      }
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    setStayAwake(false)
  }
}

struct SleepControlsView: View {
  @ObservedObject var sleep: SleepController
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Sleep controls", systemImage: "moon.zzz").font(.system(size: 13, weight: .semibold))
      control(
        "Stay awake",
        detail: "Prevents idle sleep until Mica quits. The display can still turn off.",
        binding: Binding(get: { sleep.stayAwake }, set: { sleep.setStayAwake($0) }))
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
    }
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
