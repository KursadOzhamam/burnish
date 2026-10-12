import Testing
import Foundation
import CoreKit
@testable import SystemMonitor

@Suite("DiskUsage")
struct DiskUsageTests {
    @Test("Used space is total minus free")
    func usedIsDerived() {
        let disk = DiskUsage(total: .gigabytes(1_000), free: .gigabytes(250), purgeable: .zero)
        #expect(disk.used.bytes == ByteCount.gigabytes(750).bytes)
        #expect(abs(disk.usedFraction - 0.75) < 0.001)
        #expect(abs(disk.freeFraction - 0.25) < 0.001)
    }

    @Test("Purgeable space is tracked apart from reclaimable — §10.4")
    func purgeableIsNotReclaimable() {
        // The two must stay separate: purgeable is macOS's to free, not a Burnish gain.
        let disk = DiskUsage(
            total: .gigabytes(500),
            free: .gigabytes(100),
            purgeable: .gigabytes(30),
            reclaimable: .gigabytes(12)
        )
        #expect(disk.purgeable != disk.reclaimable)
        #expect(disk.reclaimable == .gigabytes(12))
    }

    @Test("Reclaimable is nil until a scan has measured it")
    func reclaimableIsUnknownBeforeAScan() {
        let disk = DiskUsage(total: .gigabytes(500), free: .gigabytes(100), purgeable: .zero)
        #expect(disk.reclaimable == nil)
    }

    @Test("A zero-sized volume does not divide by zero")
    func emptyVolumeIsSafe() {
        let disk = DiskUsage(total: .zero, free: .zero, purgeable: .zero)
        #expect(disk.usedFraction == 0)
        #expect(disk.freeFraction == 0)
    }
}

@Suite("Reading clamps")
struct ClampTests {
    @Test("Memory pressure is clamped to 0...1")
    func pressureClamped() {
        let high = MemoryUsage(
            total: .gigabytes(8), used: .zero, compressed: .zero, swapUsed: .zero, pressure: 3
        )
        let low = MemoryUsage(
            total: .gigabytes(8), used: .zero, compressed: .zero, swapUsed: .zero, pressure: -1
        )
        #expect(high.pressure == 1)
        #expect(low.pressure == 0)
    }

    @Test("CPU load and every per-core value are clamped to 0...1")
    func cpuClamped() {
        let load = CPULoad(total: 4.2, perCore: [-0.5, 0.5, 9])
        #expect(load.total == 1)
        #expect(load.perCore == [0, 0.5, 1])
    }

    @Test("Battery values are clamped and the cycle count never goes negative")
    func batteryClamped() {
        let battery = BatteryInfo(charge: 1.8, health: -0.2, cycleCount: -5, isCharging: true)
        #expect(battery.charge == 1)
        #expect(battery.health == 0)
        #expect(battery.cycleCount == 0)
    }

    @Test("Core count is at least one")
    func coreCountFloor() {
        #expect(MachineInfo(model: "x", osVersion: "y", processorCoreCount: 0).processorCoreCount == 1)
    }
}

@Suite("MockSystemMonitor")
struct MockSystemMonitorTests {
    @Test("Streaming stops when the task is cancelled — §8 requires polling to end with the view")
    func streamStopsOnCancellation() async {
        let monitor = MockSystemMonitor()
        let task = Task {
            var count = 0
            for await _ in monitor.stream(interval: .milliseconds(10)) {
                count += 1
                if count >= 3 { break }
            }
            return count
        }
        let received = await task.value
        #expect(received == 3)
    }

    @Test("Successive readings stay within plausible bounds")
    func readingsStayBounded() async {
        let monitor = MockSystemMonitor()
        var seen = 0
        for await reading in monitor.stream(interval: .milliseconds(5)) {
            #expect(reading.cpu.total >= 0 && reading.cpu.total <= 1)
            #expect(reading.memory.pressure >= 0 && reading.memory.pressure <= 1)
            #expect(reading.cpu.history.count <= 60)
            seen += 1
            if seen >= 5 { break }
        }
        #expect(seen == 5)
    }
}
