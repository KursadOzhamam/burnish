import Testing
import Foundation
import CoreKit
@testable import SystemMonitor

@Suite("CPU load arithmetic")
struct CPULoadTests {
    private func ticks(user: UInt64 = 0, system: UInt64 = 0, idle: UInt64 = 0, nice: UInt64 = 0)
        -> Sampling.CPUTicks {
        Sampling.CPUTicks(user: user, system: system, idle: idle, nice: nice)
    }

    @Test("A fully busy interval reads as 100%")
    func fullyBusy() {
        let before = ticks(user: 100, idle: 100)
        let after = ticks(user: 200, idle: 100)
        #expect(Sampling.load(from: before, to: after) == 1)
    }

    @Test("A fully idle interval reads as 0%")
    func fullyIdle() {
        let before = ticks(user: 100, idle: 100)
        let after = ticks(user: 100, idle: 200)
        #expect(Sampling.load(from: before, to: after) == 0)
    }

    @Test("A half-busy interval reads as 50%")
    func halfBusy() {
        let before = ticks(user: 0, idle: 0)
        let after = ticks(user: 50, idle: 50)
        #expect(Sampling.load(from: before, to: after) == 0.5)
    }

    @Test("Nice time counts as busy")
    func niceCountsAsBusy() {
        let before = ticks()
        let after = ticks(idle: 50, nice: 50)
        #expect(Sampling.load(from: before, to: after) == 0.5)
    }

    @Test("Two identical readings report nothing rather than a misleading zero")
    func noElapsedTicksReportsNil() {
        let same = ticks(user: 10, idle: 10)
        #expect(Sampling.load(from: same, to: same) == nil)
    }

    @Test("A counter reset is reported as nothing, not as a spike")
    func counterResetReportsNil() {
        let before = ticks(user: 1_000, idle: 1_000)
        let after = ticks(user: 5, idle: 5)
        #expect(Sampling.load(from: before, to: after) == nil)
    }

    @Test("Per-core loads pair by index")
    func perCoreLoads() throws {
        let before = [ticks(user: 0, idle: 0), ticks(user: 0, idle: 0)]
        let after = [ticks(user: 100, idle: 0), ticks(user: 0, idle: 100)]
        let loads = try #require(Sampling.loads(from: before, to: after))
        #expect(loads == [1, 0])
    }

    @Test("A changed core count reports nothing rather than mispairing")
    func coreCountChangeReportsNil() {
        let before = [ticks(user: 0, idle: 0)]
        let after = [ticks(user: 1, idle: 1), ticks(user: 1, idle: 1)]
        #expect(Sampling.loads(from: before, to: after) == nil)
    }

    @Test("An empty previous sample reports nothing")
    func emptyPreviousReportsNil() {
        #expect(Sampling.loads(from: [], to: []) == nil)
    }
}

@Suite("Network throughput")
struct ThroughputTests {
    @Test("Bytes over elapsed seconds give bytes per second")
    func basicRate() {
        let rate = Sampling.throughput(previousBytes: 1_000, currentBytes: 3_000, elapsed: 2)
        #expect(rate.bytes == 1_000)
    }

    @Test("An interface counter reset reads as zero, not as a spike")
    func counterResetIsZero() {
        let rate = Sampling.throughput(previousBytes: 10_000, currentBytes: 5, elapsed: 1)
        #expect(rate == .zero)
    }

    @Test("Zero or negative elapsed time yields zero")
    func zeroElapsedIsZero() {
        #expect(Sampling.throughput(previousBytes: 0, currentBytes: 100, elapsed: 0) == .zero)
        #expect(Sampling.throughput(previousBytes: 0, currentBytes: 100, elapsed: -1) == .zero)
    }

    @Test("No change means no traffic")
    func noChangeIsZero() {
        #expect(Sampling.throughput(previousBytes: 500, currentBytes: 500, elapsed: 1) == .zero)
    }
}

@Suite("Memory arithmetic")
struct MemoryTests {
    private let pageSize: UInt64 = 16_384

    private func pages(
        active: UInt64 = 0,
        wired: UInt64 = 0,
        compressed: UInt64 = 0,
        free: UInt64 = 0,
        inactive: UInt64 = 0,
        speculative: UInt64 = 0
    ) -> Sampling.MemoryPages {
        Sampling.MemoryPages(
            active: active, wired: wired, compressed: compressed,
            free: free, inactive: inactive, speculative: speculative
        )
    }

    @Test("Used memory counts active, wired and compressed pages")
    func usedMemoryComposition() {
        let used = Sampling.memoryUsed(
            pages: pages(active: 10, wired: 5, compressed: 5),
            pageSize: pageSize
        )
        #expect(used.bytes == Int64(20 * pageSize))
    }

    @Test("Inactive and speculative pages are excluded — §10.4 forbids inflating usage")
    func reclaimablePagesAreExcluded() {
        let withReclaimable = Sampling.memoryUsed(
            pages: pages(active: 10, inactive: 100, speculative: 100),
            pageSize: pageSize
        )
        #expect(withReclaimable.bytes == Int64(10 * pageSize))
    }

    @Test("Pressure comes from wired and compressed pages, not from total usage")
    func pressureComposition() {
        let physical: UInt64 = 100 * 16_384
        // 40 held pages out of 100 → 0.4, even though 90 pages are in use.
        let pressure = Sampling.memoryPressure(
            pages: pages(active: 50, wired: 20, compressed: 20),
            pageSize: pageSize,
            physicalMemory: physical
        )
        #expect(abs(pressure - 0.4) < 0.001)
    }

    @Test("Pressure is clamped to 0...1")
    func pressureIsClamped() {
        let pressure = Sampling.memoryPressure(
            pages: pages(wired: 1_000),
            pageSize: pageSize,
            physicalMemory: 16_384
        )
        #expect(pressure == 1)
    }

    @Test("Unknown physical memory yields zero rather than dividing by zero")
    func zeroPhysicalMemoryIsSafe() {
        #expect(Sampling.memoryPressure(pages: pages(wired: 5), pageSize: pageSize, physicalMemory: 0) == 0)
    }
}

@Suite("Rolling history")
struct HistoryTests {
    @Test("History keeps the newest samples up to the limit")
    func keepsNewest() {
        var history: [Double] = []
        for value in 0..<70 {
            history = Sampling.appending(Double(value), to: history, limit: 60)
        }
        #expect(history.count == 60)
        #expect(history.first == 10)
        #expect(history.last == 69)
    }

    @Test("A zero limit keeps nothing")
    func zeroLimitKeepsNothing() {
        #expect(Sampling.appending(1, to: [1, 2, 3], limit: 0).isEmpty)
    }

    @Test("A short history is returned intact")
    func shortHistoryIsKept() {
        #expect(Sampling.appending(2, to: [1], limit: 60) == [1, 2])
    }
}
