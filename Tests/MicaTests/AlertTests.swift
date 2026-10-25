import Foundation
import Testing
import UserNotifications
@testable import Mica

@Suite struct AlertTests {
  @Test func durationRequiresConsecutiveObservedSamples() {
    var engine = AlertEngine()
    let rule = AlertRule(metric: .cpu, enabled: true, threshold: 80, duration: 10, cooldown: 30)
    #expect(engine.evaluate([.cpu: 90], rules: [rule], time: 0).isEmpty)
    #expect(engine.evaluate([.cpu: 90], rules: [rule], time: 5).isEmpty)
    #expect(engine.evaluate([.cpu: 90], rules: [rule], time: 10).count == 1)
    #expect(engine.evaluate([.cpu: 90], rules: [rule], time: 20).isEmpty)
  }
  @Test func recoveryAndCooldownBothLimitRepeatedAlerts() {
    var engine = AlertEngine()
    let rule = AlertRule(metric: .cpu, enabled: true, threshold: 80, duration: 0, cooldown: 20)
    #expect(engine.evaluate([.cpu: 90], rules: [rule], time: 0).count == 1)
    #expect(engine.evaluate([.cpu: 90], rules: [rule], time: 10).isEmpty)
    #expect(engine.evaluate([.cpu: 0], rules: [rule], time: 11).isEmpty)
    #expect(engine.evaluate([.cpu: 90], rules: [rule], time: 12).isEmpty)
    #expect(engine.evaluate([.cpu: 90], rules: [rule], time: 20).count == 1)
    #expect(engine.evaluate([.cpu: 90], rules: [rule], time: 30).isEmpty)
  }
  @Test func missingReadingsAndSleepGapsResetPendingDuration() {
    var engine = AlertEngine()
    let rule = AlertRule(metric: .cpu, enabled: true, threshold: 80, duration: 10)
    _ = engine.evaluate([.cpu: 90], rules: [rule], time: 0)
    _ = engine.evaluate([:], rules: [rule], time: 5)
    #expect(engine.evaluate([.cpu: 90], rules: [rule], time: 10).isEmpty)
    #expect(engine.evaluate([.cpu: 90], rules: [rule], time: 25).isEmpty)
    #expect(engine.evaluate([.cpu: 90], rules: [rule], time: 35).count == 1)
    engine.resetPending()
    #expect(engine.evaluate([.cpu: 90], rules: [rule], time: 100).isEmpty)
  }
  @Test func ruleEditsAndDisableResetPendingState() {
    var engine = AlertEngine()
    var rule = AlertRule(metric: .cpu, enabled: true, threshold: 80, duration: 10)
    _ = engine.evaluate([.cpu: 90], rules: [rule], time: 0)
    rule.threshold = 85
    #expect(engine.evaluate([.cpu: 90], rules: [rule], time: 5).isEmpty)
    #expect(engine.evaluate([.cpu: 90], rules: [rule], time: 10).isEmpty)
    rule.enabled = false
    _ = engine.evaluate([.cpu: 90], rules: [rule], time: 15)
    rule.enabled = true
    #expect(engine.evaluate([.cpu: 90], rules: [rule], time: 20).isEmpty)
  }
  @Test func invalidConfigurationAndNonfiniteDataCannotFire() {
    var engine = AlertEngine()
    var rule = AlertRule(metric: .cpu, enabled: true, threshold: .nan, duration: 0)
    #expect(engine.evaluate([.cpu: 99], rules: [rule], time: 0).isEmpty)
    rule.threshold = 80; rule.duration = -1
    #expect(engine.evaluate([.cpu: 99], rules: [rule], time: 1).isEmpty)
    rule.duration = 0
    #expect(engine.evaluate([.cpu: .nan], rules: [rule], time: 2).isEmpty)
  }
  @Test func lowerBoundsTreatRealZeroAsData() {
    var engine = AlertEngine()
    let rules = [
      AlertRule(metric: .batteryLow, enabled: true, threshold: 20, duration: 0),
      AlertRule(metric: .diskFree, enabled: true, threshold: 10, duration: 0)
    ]
    #expect(engine.evaluate([:], rules: rules, time: 0).isEmpty)
    #expect(engine.evaluate([.batteryLow: 0, .diskFree: 0], rules: rules, time: 1).count == 2)
  }
  @Test func defaultsDisabledAndMissingSnapshotValuesDoNotNotify() {
    let delivery = FakeAlertDelivery()
    let alerts = AlertController(delivery: delivery)
    var preferences = Preferences()
    #expect(!preferences.alertsEnabled)
    #expect(preferences.alertRules.allSatisfy { !$0.enabled })
    preferences.alertsEnabled = true
    for index in preferences.alertRules.indices {
      preferences.alertRules[index].enabled = true
      preferences.alertRules[index].duration = 0
    }
    alerts.consume(Snapshot(), preferences: preferences, time: 0)
    #expect(delivery.sent.isEmpty)
    #expect(alerts.recent.isEmpty)
  }
  @Test func recentHistoryIsBoundedAndTestMessagesAreIdentified() {
    let delivery = FakeAlertDelivery()
    let alerts = AlertController(delivery: delivery)
    var preferences = Preferences()
    preferences.alertsEnabled = true
    preferences.alertRules = [AlertRule(metric: .cpu, enabled: true, threshold: 80, duration: 0, cooldown: 0)]
    var snapshot = Snapshot(); snapshot.cpuAvailable = true
    for index in 0..<50 {
      snapshot.cores = [CoreLoad(user: 0.9, system: 0)]
      alerts.consume(snapshot, preferences: preferences, time: Double(index * 2))
      snapshot.cores = [CoreLoad(user: 0, system: 0)]
      alerts.consume(snapshot, preferences: preferences, time: Double(index * 2 + 1))
    }
    #expect(delivery.sent.count == 50)
    #expect(alerts.recent.count == 20)
    alerts.sendTest()
    #expect(alerts.recent.first?.isTest == true)
    #expect(alerts.recent.first?.title == "Test notification")
  }
}
private final class FakeAlertDelivery: AlertDelivery {
  var sent: [AlertEvent] = []
  func status(_ completion: @escaping (UNAuthorizationStatus) -> Void) { completion(.authorized) }
  func request(_ completion: @escaping (Bool, Error?) -> Void) { completion(true, nil) }
  func send(_ event: AlertEvent, completion: @escaping (String?) -> Void) { sent.append(event); completion(nil) }
}
