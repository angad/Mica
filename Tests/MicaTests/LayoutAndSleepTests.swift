import AppKit
import Foundation
import IOKit.pwr_mgt
import Testing

@testable import Mica

@Suite struct LayoutAndSleepTests {
  @Test func powerRowsShareAColumnAndRemainIndependentlyClickable() throws {
    var sample = Snapshot()
    sample.cores = Array(repeating: CoreLoad(user: 0.3, system: 0.1), count: 8)
    let prefs = Preferences()
    let regions = MeterPainter.regions(sample, prefs)
    let input = try #require(regions.first { $0.meter == .input })
    let output = try #require(regions.first { $0.meter == .consumption })
    #expect(input.rect.minX == output.rect.minX)
    #expect(input.rect.minY == output.rect.maxY)
    #expect(
      MeterPainter.region(at: NSPoint(x: input.rect.midX, y: 18), in: regions)?.meter == .input)
    #expect(
      MeterPainter.region(at: NSPoint(x: output.rect.midX, y: 6), in: regions)?.meter
        == .consumption)
    #expect(MeterPainter.image(sample, prefs, dark: false).size.width <= 330)
    for visible in [Meter.input, .consumption] {
      var one = prefs
      one.enabled = [visible]
      let single = try #require(MeterPainter.regions(sample, one).first)
      #expect(single.rect.height == 24)
      #expect(single.meter == visible)
    }
  }
  @Test func popoversFitSmallScreensWithoutReducingContentWidth() {
    let ideal = NSSize(width: 320, height: 560)
    let small = PopoverLayout.size(ideal: ideal, available: NSSize(width: 900, height: 280))
    #expect(small.width == 320)
    #expect(small.height == 252)
    let normal = PopoverLayout.size(ideal: ideal, available: NSSize(width: 1440, height: 870))
    #expect(normal == ideal)
  }
  @Test func stayAwakeUsesOneAssertionAndReleasesItOnStop() {
    let backend = FakeSleepBackend()
    let controller = SleepController(backend: backend, observe: false)
    controller.setStayAwake(true)
    controller.setStayAwake(true)
    #expect(controller.stayAwake)
    #expect(backend.created == 1)
    controller.stop()
    #expect(!controller.stayAwake)
    #expect(backend.released == [42])
  }
  @Test func failedAwakeRequestDoesNotClaimToBeEnabled() {
    let backend = FakeSleepBackend()
    backend.failCreate = true
    let controller = SleepController(backend: backend, observe: false)
    controller.setStayAwake(true)
    #expect(!controller.stayAwake)
    #expect(controller.errorMessage != nil)
  }
  @Test func lidToggleShowsVerifiedSystemStateAndTracksExternalChanges() {
    let backend = FakeSleepBackend()
    let controller = SleepController(backend: backend, observe: false)
    controller.setLidSleepDisabled(true)
    #expect(controller.lidSleepDisabled == true)
    #expect(backend.requests == [true])
    backend.disabled = false
    controller.refresh()
    #expect(controller.lidSleepDisabled == false)
    controller.stop()
    #expect(backend.requests == [true])  // Quitting does not silently change a global setting.
  }
  @Test func cancelledOrUnconfirmedLidRequestsDoNotLieAboutState() {
    let backend = FakeSleepBackend()
    backend.result = .failure(.cancelled)
    let controller = SleepController(backend: backend, observe: false)
    controller.setLidSleepDisabled(true)
    #expect(controller.lidSleepDisabled == false)
    #expect(controller.errorMessage == nil)
    #expect(!controller.changingLidSleep)
    backend.result = .success(())
    backend.applyChange = false
    controller.setLidSleepDisabled(true)
    #expect(controller.lidSleepDisabled == false)
    #expect(controller.errorMessage != nil)
  }
  @Test func concurrentAuthorizationRequestsArePrevented() {
    let backend = FakeSleepBackend()
    backend.deferResult = true
    let controller = SleepController(backend: backend, observe: false)
    controller.setLidSleepDisabled(true)
    controller.setLidSleepDisabled(true)
    #expect(controller.changingLidSleep)
    #expect(backend.requests == [true])
    backend.finish?(.failure(.cancelled))
    #expect(!controller.changingLidSleep)
  }
  @Test func authorizationCommandsAreLimitedToTheTwoSleepValues() {
    #expect(
      MacSleepBackend.authorizationScript(disabled: true).contains(
        "/usr/bin/pmset -a disablesleep 1"))
    #expect(
      MacSleepBackend.authorizationScript(disabled: false).contains(
        "/usr/bin/pmset -a disablesleep 0"))
  }
  @Test func macOSCanCompileBothAuthorizationPromptsWithoutExecutingThem() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for disabled in [true, false] {
      let compiler = Process()
      compiler.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
      compiler.arguments = [
        "-o", directory.appendingPathComponent("prompt.scpt").path,
        "-e", MacSleepBackend.authorizationScript(disabled: disabled),
      ]
      let errors = Pipe()
      compiler.standardError = errors
      try compiler.run()
      let data = errors.fileHandleForReading.readDataToEndOfFile()
      compiler.waitUntilExit()
      #expect(compiler.terminationStatus == 0, "\(String(decoding: data, as: UTF8.self))")
    }
  }
}

private final class FakeSleepBackend: SleepBackend {
  var supportsClosedLid = true
  var disabled: Bool? = false
  var created = 0
  var released: [IOPMAssertionID] = []
  var requests: [Bool] = []
  var failCreate = false
  var applyChange = true
  var deferResult = false
  var finish: ((Result<Void, SleepControlError>) -> Void)?
  var result: Result<Void, SleepControlError> = .success(())
  func beginStayAwake() throws -> IOPMAssertionID {
    if failCreate { throw SleepControlError.failed("Test failure") }
    created += 1
    return 42
  }
  func endStayAwake(_ assertion: IOPMAssertionID) throws { released.append(assertion) }
  func readSleepDisabled() -> Bool? { disabled }
  func setSleepDisabled(
    _ value: Bool, completion: @escaping (Result<Void, SleepControlError>) -> Void
  ) {
    requests.append(value)
    if deferResult {
      finish = completion
      return
    }
    if case .success = result, applyChange { disabled = value }
    completion(result)
  }
}
