import Foundation
import IOKit.pwr_mgt
import Testing
@testable import Mica

@Suite struct TimedSessionTests {
  @Test func replacingTimerReusesTheAssertion() {
    let backend = SessionBackend()
    let now = Date(timeIntervalSince1970: 100)
    let controller = SleepController(backend: backend, observe: false, now: { now })
    controller.startSession(minutes: 15)
    controller.startSession(minutes: 30)
    #expect(backend.created == 1)
    #expect(controller.sessionDeadline == now.addingTimeInterval(1800))
    controller.setStayAwake(true)
    #expect(controller.sessionDeadline == nil)
    #expect(backend.created == 1)
    controller.stop()
    #expect(backend.released == 1)
    #expect(backend.lidRequests.isEmpty)
  }
  @Test func deadlineExpiresAndReleasesWithoutChangingPersistentSleep() {
    let backend = SessionBackend()
    var now = Date(timeIntervalSince1970: 100)
    let controller = SleepController(backend: backend, observe: false, now: { now })
    controller.startSession(minutes: 1)
    now = now.addingTimeInterval(59)
    controller.checkSession()
    #expect(controller.stayAwake)
    now = now.addingTimeInterval(1)
    controller.checkSession()
    #expect(!controller.stayAwake)
    #expect(controller.sessionDeadline == nil)
    #expect(controller.sessionMessage == "Timed session ended.")
    #expect(backend.released == 1)
    #expect(backend.lidRequests.isEmpty)
  }
  @Test func pastOrInvalidRequestsPreserveAnExistingSession() {
    let backend = SessionBackend()
    let now = Date(timeIntervalSince1970: 100)
    let controller = SleepController(backend: backend, observe: false, now: { now })
    controller.startSession(minutes: 30)
    let deadline = controller.sessionDeadline
    controller.startSession(minutes: 0)
    controller.startSession(until: now.addingTimeInterval(-1))
    #expect(controller.stayAwake)
    #expect(controller.sessionDeadline == deadline)
    #expect(controller.errorMessage != nil)
    #expect(backend.created == 1)
  }
  @Test func wakingAfterDeadlineEndsTheSession() {
    let backend = SessionBackend()
    var now = Date(timeIntervalSince1970: 100)
    let controller = SleepController(backend: backend, observe: false, now: { now })
    controller.startSession(minutes: 30)
    now = now.addingTimeInterval(4000)
    controller.checkSession()
    #expect(!controller.stayAwake)
    #expect(backend.released == 1)
  }
  @Test func batteryCutoffRequiresKnownBatteryPowerAndEnabledThreshold() {
    let backend = SessionBackend()
    let controller = SleepController(backend: backend, observe: false)
    controller.startSession(minutes: 30)
    var battery = BatteryReading(id: "fixture", name: "Fixture", chargePercent: 10)
    controller.enforceBatteryLimit(nil, threshold: 20)
    controller.enforceBatteryLimit(battery, threshold: 20)
    #expect(controller.stayAwake)
    battery.externalPower = true
    controller.enforceBatteryLimit(battery, threshold: 20)
    #expect(controller.stayAwake)
    battery.externalPower = false
    controller.enforceBatteryLimit(battery, threshold: 0)
    #expect(controller.stayAwake)
    controller.enforceBatteryLimit(battery, threshold: 20)
    #expect(!controller.stayAwake)
    #expect(backend.lidRequests.isEmpty)
  }
  @Test func failedReleaseDoesNotClaimTheSessionEnded() {
    let backend = SessionBackend()
    let controller = SleepController(backend: backend, observe: false)
    controller.startSession(minutes: 30)
    backend.failRelease = true
    controller.setStayAwake(false)
    #expect(controller.stayAwake)
    #expect(controller.sessionDeadline != nil)
    #expect(controller.errorMessage != nil)
    backend.failRelease = false
    controller.stop()
    #expect(!controller.stayAwake)
  }
}
private final class SessionBackend: SleepBackend {
  var supportsClosedLid = true
  var created = 0
  var released = 0
  var failRelease = false
  var lidRequests: [Bool] = []
  func beginStayAwake() throws -> IOPMAssertionID { created += 1; return 42 }
  func endStayAwake(_ assertion: IOPMAssertionID) throws {
    if failRelease { throw SleepControlError.failed("Fixture release failure") }
    released += 1
  }
  func readSleepDisabled() -> Bool? { false }
  func setSleepDisabled(_ disabled: Bool, completion: @escaping (Result<Void, SleepControlError>) -> Void) {
    lidRequests.append(disabled); completion(.success(()))
  }
}
