import AppKit
import Combine
import SwiftUI
import UserNotifications

enum AlertMetric: String, Codable, CaseIterable, Identifiable {
  case cpu, memoryPressure, diskFree, batteryLow, batteryHigh, temperature
  var id: String { rawValue }
  var title: String {
    switch self {
    case .cpu: "CPU usage"
    case .memoryPressure: "Memory pressure"
    case .diskFree: "Home volume free space"
    case .batteryLow: "Battery below"
    case .batteryHigh: "Battery above"
    case .temperature: "Selected temperature sensor"
    }
  }
  var unit: String {
    switch self {
    case .cpu, .batteryLow, .batteryHigh: "%"
    case .diskFree: "GiB"
    case .temperature: "°C"
    case .memoryPressure: ""
    }
  }
  var range: ClosedRange<Double> {
    switch self {
    case .cpu: 1...100
    case .memoryPressure: 2...4
    case .diskFree: 0.1...4096
    case .batteryLow, .batteryHigh: 0...100
    case .temperature: 1...130
    }
  }
  func matches(_ value: Double, threshold: Double) -> Bool {
    switch self {
    case .diskFree, .batteryLow: value <= threshold
    default: value >= threshold
    }
  }
}
struct AlertRule: Codable, Equatable, Identifiable {
  var metric: AlertMetric
  var enabled = false
  var threshold: Double
  var duration: Double = 30
  var cooldown: Double = 300
  var id: String { metric.rawValue }
  var valid: Bool {
    threshold.isFinite && metric.range.contains(threshold)
      && duration.isFinite && (0...3600).contains(duration)
      && cooldown.isFinite && (0...86400).contains(cooldown)
  }
  static var defaults: [AlertRule] {
    [
      AlertRule(metric: .cpu, threshold: 80),
      AlertRule(metric: .memoryPressure, threshold: 2, duration: 10),
      AlertRule(metric: .diskFree, threshold: 10, duration: 60),
      AlertRule(metric: .batteryLow, threshold: 20, duration: 10),
      AlertRule(metric: .batteryHigh, threshold: 80, duration: 10),
      AlertRule(metric: .temperature, threshold: 90),
    ]
  }
}
struct AlertEvent: Identifiable {
  var id = UUID()
  var metric: AlertMetric
  var value: Double
  var threshold: Double
  var date = Date()
  var isTest = false
  var title: String { isTest ? "Test notification" : metric.title }
  var message: String {
    if isTest { return "Mica can deliver local notifications." }
    switch metric {
    case .memoryPressure: return "Memory pressure is \(value >= 4 ? "critical" : "elevated")."
    case .diskFree: return "\(bytes(value * 1_073_741_824)) is available on the home volume."
    case .cpu: return String(format: "CPU usage is %.1f%% (threshold %.0f%%).", value, threshold)
    case .batteryLow, .batteryHigh: return String(format: "Battery charge is %.0f%% (threshold %.0f%%).", value, threshold)
    case .temperature: return String(format: "Selected sensor is %.1f°C (threshold %.0f°C).", value, threshold)
    }
  }
}
struct AlertEngine {
  private struct State {
    var rule: AlertRule
    var since: Double?
    var lastFired: Double?
    var latched = false
  }
  private var states: [AlertMetric: State] = [:]
  private var previousTime: Double?
  mutating func resetPending() {
    for key in Array(states.keys) { states[key]?.since = nil }
    previousTime = nil
  }
  mutating func evaluate(_ values: [AlertMetric: Double], rules: [AlertRule], time: Double) -> [AlertEvent] {
    guard time.isFinite else { return [] }
    if let old = previousTime, time < old { states = [:] }
    let gap = previousTime.map { time - $0 > 10 } ?? false
    previousTime = time
    states = states.filter { key, _ in rules.contains { $0.metric == key && $0.enabled && $0.valid } }
    var events: [AlertEvent] = []
    for rule in rules where rule.enabled && rule.valid {
      var state = states[rule.metric].flatMap { $0.rule == rule ? $0 : nil } ?? State(rule: rule)
      if gap { state.since = nil }
      guard let value = values[rule.metric], value.isFinite else {
        state.since = nil
        states[rule.metric] = state
        continue
      }
      if !rule.metric.matches(value, threshold: rule.threshold) {
        state.since = nil; state.latched = false
      } else if !state.latched {
        if state.since == nil { state.since = time }
        if time - state.since! >= rule.duration,
          state.lastFired.map({ time - $0 >= rule.cooldown }) ?? true {
          state.lastFired = time; state.latched = true
          events.append(AlertEvent(metric: rule.metric, value: value, threshold: rule.threshold))
        }
      }
      states[rule.metric] = state
    }
    return events
  }
}
protocol AlertDelivery {
  func status(_ completion: @escaping (UNAuthorizationStatus) -> Void)
  func request(_ completion: @escaping (Bool, Error?) -> Void)
  func send(_ event: AlertEvent, completion: @escaping (String?) -> Void)
}
final class MacAlertDelivery: NSObject, AlertDelivery, UNUserNotificationCenterDelegate {
  private let center = UNUserNotificationCenter.current()
  override init() { super.init(); center.delegate = self }
  func status(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
    center.getNotificationSettings { completion($0.authorizationStatus) }
  }
  func request(_ completion: @escaping (Bool, Error?) -> Void) {
    center.requestAuthorization(options: [.alert], completionHandler: completion)
  }
  func send(_ event: AlertEvent, completion: @escaping (String?) -> Void) {
    center.getNotificationSettings { [self] settings in
      guard settings.authorizationStatus == .authorized else {
        completion("Notifications are not allowed. Enable Mica in System Settings → Notifications.")
        return
      }
      let content = UNMutableNotificationContent()
      content.title = "Mica: " + event.title
      content.body = event.message
      let request = UNNotificationRequest(identifier: "mica.alert." + (event.isTest ? "test" : event.metric.rawValue), content: content, trigger: nil)
      center.add(request) { completion($0?.localizedDescription) }
    }
  }
  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .list])
  }
}
final class AlertController: ObservableObject {
  @Published private(set) var recent: [AlertEvent] = []
  @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
  @Published private(set) var deliveryError: String?
  private var delivery: AlertDelivery?
  private var engine = AlertEngine()
  init(delivery: AlertDelivery? = nil) { self.delivery = delivery }
  func start() {
    if delivery == nil { delivery = MacAlertDelivery() }
    refreshAuthorization()
  }
  func refreshAuthorization() {
    delivery?.status { [weak self] status in DispatchQueue.main.async { self?.authorization = status } }
  }
  func requestPermission() {
    delivery?.request { [weak self] _, error in
      DispatchQueue.main.async {
        self?.deliveryError = error?.localizedDescription
        self?.refreshAuthorization()
      }
    }
  }
  func resetPending() { engine.resetPending() }
  func consume(_ snapshot: Snapshot, preferences: Preferences, time: Double) {
    guard preferences.alertsEnabled else { engine = AlertEngine(); return }
    if delivery == nil { start() }
    var values: [AlertMetric: Double] = [:]
    if snapshot.cpuAvailable { values[.cpu] = snapshot.cpu * 100 }
    if [1, 2, 4].contains(snapshot.pressure), snapshot.memoryTotal > 0 {
      values[.memoryPressure] = Double(snapshot.pressure)
    }
    if let free = snapshot.diskFreeBytes { values[.diskFree] = free / 1_073_741_824 }
    if let percent = snapshot.battery?.chargePercent, (0...100).contains(percent) {
      values[.batteryLow] = percent; values[.batteryHigh] = percent
    }
    if let temperature = snapshot.temperature { values[.temperature] = temperature }
    for event in engine.evaluate(values, rules: preferences.alertRules, time: time) { record(event) }
  }
  private func record(_ event: AlertEvent) {
    recent.insert(event, at: 0)
    if recent.count > 20 { recent.removeLast(recent.count - 20) }
    delivery?.send(event) { [weak self] error in
      DispatchQueue.main.async { self?.deliveryError = error }
    }
  }
  func sendTest() { record(AlertEvent(metric: .cpu, value: 0, threshold: 0, isTest: true)) }
  func clear() { recent = []; deliveryError = nil }
}

struct AlertsView: View {
  @ObservedObject var settings: Settings
  @ObservedObject var alerts: AlertController
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Toggle("Evaluate alert rules", isOn: $settings.value.alertsEnabled).toggleStyle(.switch)
      HStack {
        Text(permissionText).font(.system(size: 11)).foregroundColor(.secondary)
        Spacer()
        Button("Request notification permission") { alerts.requestPermission() }
      }
      Text("Rules run locally. A rule notifies once while its condition remains true. It must recover before notifying again; the cooldown also limits repeats.")
        .font(.system(size: 11)).foregroundColor(.secondary)
      ForEach($settings.value.alertRules) { $rule in
        VStack(alignment: .leading, spacing: 8) {
          Toggle(rule.metric.title, isOn: $rule.enabled).toggleStyle(.switch)
            .font(.system(size: 12, weight: .semibold))
          HStack {
            Text(rule.metric == .diskFree || rule.metric == .batteryLow ? "At or below" : "At or above")
            Spacer()
            if rule.metric == .memoryPressure {
              Picker("Pressure level", selection: $rule.threshold) {
                Text("Elevated").tag(2.0); Text("Critical").tag(4.0)
              }.labelsHidden().frame(width: 160)
            } else {
              TextField("Threshold", value: $rule.threshold, format: .number).frame(width: 70)
                .accessibilityLabel(rule.metric.title + " threshold")
              Text(rule.metric.unit).frame(width: 30, alignment: .leading)
            }
          }.font(.system(size: 11))
          Stepper("For \(String(format: "%.0f", rule.duration)) seconds", value: $rule.duration, in: 0...600, step: 5)
            .accessibilityLabel(rule.metric.title + " duration")
          Stepper("Cooldown \(String(format: "%.0f", rule.cooldown / 60)) minutes", value: $rule.cooldown, in: 0...3600, step: 60)
            .accessibilityLabel(rule.metric.title + " cooldown")
          if !rule.valid {
            Text("Threshold is outside the supported range; this rule will not run.").foregroundColor(.red)
          }
        }.font(.system(size: 11)).padding(14).meterGlass(radius: 12)
      }
      HStack {
        Button("Send test notification") { alerts.sendTest() }.disabled(alerts.authorization != .authorized)
        Spacer()
        Button("Clear recent alerts") { alerts.clear() }
      }
      if let error = alerts.deliveryError { Text(error).font(.system(size: 11)).foregroundColor(.red) }
      Text("Recent alerts").font(.headline)
      if alerts.recent.isEmpty { Text("No alerts in this session.").font(.system(size: 11)).foregroundColor(.secondary) }
      ForEach(alerts.recent) { event in
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text(event.title).fontWeight(.medium)
            Spacer()
            Text(event.date, style: .time).foregroundColor(.secondary)
          }
          Text(event.message).foregroundColor(.secondary)
        }.font(.system(size: 11))
      }
    }.onAppear { alerts.start() }
  }
  private var permissionText: String {
    switch alerts.authorization {
    case .authorized: "Notifications allowed"
    case .denied: "Notifications blocked in System Settings"
    default: "Notification permission has not been granted"
    }
  }
}
