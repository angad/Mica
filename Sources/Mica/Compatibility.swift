import AppKit
import ServiceManagement
import SwiftUI

enum AppVersion {
  static var current: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0"
  }
}
private struct MeterGlass: ViewModifier {
  var tint: Color
  var radius: CGFloat
  @ViewBuilder func body(content: Content) -> some View {
    if #available(macOS 26, *) {
      content.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: radius))
    } else if #available(macOS 12, *) {
      content.background(.thinMaterial, in: RoundedRectangle(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius).stroke(tint.opacity(0.3), lineWidth: 0.5))
    } else {
      content.background(
        RoundedRectangle(cornerRadius: radius)
          .fill(Color(NSColor.controlBackgroundColor)))
    }
  }
}
extension View {
  func meterGlass(tint: Color = .clear, radius: CGFloat = 12) -> some View {
    modifier(MeterGlass(tint: tint, radius: radius))
  }
  @ViewBuilder func meterNumericTransition() -> some View {
    if #available(macOS 14, *) { contentTransition(.numericText()) } else { self }
  }
}
struct MeterButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.meterGlass(radius: 13).opacity(configuration.isPressed ? 0.6 : 1)
  }
}
/// SMAppService is used on Ventura+. Big Sur/Monterey use a per-user RunAtLoad
/// agent, with no privileged helper and no launchd keep-alive loop.
enum LoginStartup {
  static var agentURL: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/LaunchAgents/sg.angad.Mica.plist")
  }
  static var enabled: Bool {
    if #available(macOS 13, *) { return SMAppService.mainApp.status == .enabled }
    return FileManager.default.fileExists(atPath: agentURL.path)
  }
  static func setEnabled(_ enabled: Bool) throws {
    if #available(macOS 13, *) {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } else if enabled {
      guard let executable = Bundle.main.executableURL,
        Bundle.main.bundleURL.pathExtension == "app"
      else {
        throw NSError(
          domain: "Mica", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Install Mica.app in Applications first."])
      }
      let data = try PropertyListSerialization.data(
        fromPropertyList: [
          "Label": "sg.angad.Mica", "ProgramArguments": [executable.path],
          "RunAtLoad": true, "ProcessType": "Interactive",
        ], format: .xml, options: 0)
      try FileManager.default.createDirectory(
        at: agentURL.deletingLastPathComponent(),
        withIntermediateDirectories: true)
      try data.write(to: agentURL, options: .atomic)
    } else if FileManager.default.fileExists(atPath: agentURL.path) {
      try FileManager.default.removeItem(at: agentURL)
    }
  }
  static var approvalMessage: String? {
    if #available(macOS 13, *), SMAppService.mainApp.status == .requiresApproval {
      return "Allow Mica in System Settings → General → Login Items."
    }
    return nil
  }
}

extension Color {
  static var meterMint: Color { Color(red: 0.2, green: 0.8, blue: 0.7) }
}
