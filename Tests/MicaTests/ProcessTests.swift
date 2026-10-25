import Darwin
import Foundation
import Testing
@testable import Mica

@Suite struct ProcessTests {
  @MainActor @Test func processPollingOnlyRunsWhileRequestedAndUnpaused() {
    let process = ProcessMonitor(reader: { ProcessBatch(time: 0, total: 0, counters: []) })
    #expect(!process.isPolling)
    process.setVisible(true, viewer: "settings")
    #expect(process.isPolling)
    process.setVisible(true, viewer: "popover")
    process.setVisible(false, viewer: "settings")
    #expect(process.isPolling)
    process.setPaused(true)
    #expect(!process.isPolling)
    process.setPaused(false)
    #expect(process.isPolling)
    process.setVisible(false, viewer: "popover")
    #expect(!process.isPolling)
    #expect(process.readings.isEmpty)
  }
  private func batch(_ time: Double, started: UInt64 = 1, cpu: UInt64 = 0) -> ProcessBatch {
    ProcessBatch(time: time, total: 1, counters: [
      ProcessCounter(pid: 123, started: started, name: "Fixture", cpuNanoseconds: cpu, memoryBytes: 4096)
    ])
  }
  @Test func cpuUsesDeltasAndCanExceedOneCore() throws {
    let first = batch(10, cpu: 1_000_000_000)
    let second = batch(12, cpu: 4_000_000_000)
    let reading = try #require(ProcessReader.readings(second, previous: first).first)
    #expect(reading.cpuPercent == 150)
    #expect(reading.memoryBytes == 4096)
  }
  @Test func pidReuseCounterResetAndGapsDoNotInventCpuUsage() {
    #expect(ProcessReader.readings(batch(2, started: 2, cpu: 100), previous: batch(1)).first?.cpuPercent == nil)
    #expect(ProcessReader.readings(batch(2, cpu: 2), previous: batch(1, cpu: 3)).first?.cpuPercent == nil)
    #expect(ProcessReader.readings(batch(1), previous: batch(1)).first?.cpuPercent == nil)
    #expect(ProcessReader.readings(batch(30), previous: batch(1)).first?.cpuPercent == nil)
    #expect(ProcessReader.readings(batch(1), previous: nil).first?.cpuPercent == nil)
  }
  @Test func nativeCpuCounterMatchesProcessCpuClock() throws {
    func clock() -> Double {
      var time = timespec()
      clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &time)
      return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9
    }
    let before = clock()
    let data = ProcessReader.read()
    let after = clock()
    let own = try #require(data.counters.first { $0.pid == getpid() })
    let seconds = Double(own.cpuNanoseconds) / 1e9
    #expect(seconds >= before - 0.05)
    #expect(seconds <= after + 0.05)
    #expect(own.memoryBytes > 0)
    #expect(!own.name.isEmpty)
  }
}
