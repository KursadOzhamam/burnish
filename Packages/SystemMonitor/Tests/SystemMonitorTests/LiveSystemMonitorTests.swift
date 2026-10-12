import Testing
import Foundation
import CoreKit
@testable import SystemMonitor

/// Readings from the machine running the suite.
///
/// These assert *plausibility*, never exact values — the numbers legitimately differ on every
/// run and every Mac. What they prove is that each reader returns something sane rather than
/// zero, garbage, or a crash, which is the failure mode that actually matters: a dashboard
/// quietly showing 0% CPU forever looks like a working app.
@Suite("Live readings", .serialized)
struct LiveSystemMonitorTests {

    @Test("The boot volume reports a real capacity")
    func diskIsRead() throws {
        let disk = try #require(KernelReaders.diskUsage())

        #expect(disk.total.bytes > 0)
        #expect(disk.free.bytes >= 0)
        #expect(disk.free.bytes <= disk.total.bytes)
        #expect(disk.usedFraction >= 0 && disk.usedFraction <= 1)
    }

    @Test("Purgeable space is reported separately and never exceeds the volume")
    func purgeableIsSeparate() throws {
        let disk = try #require(KernelReaders.diskUsage())
        #expect(disk.purgeable.bytes >= 0)
        #expect(disk.purgeable.bytes <= disk.total.bytes)
        // It is a different figure from free space by construction.
        #expect(disk.reclaimable == nil, "nothing scanned yet, so nothing is claimed")
    }

    @Test("Memory pages come back and add up to something plausible")
    func memoryIsRead() throws {
        let reading = try #require(KernelReaders.memoryPages())

        #expect(reading.pageSize >= 4_096)
        #expect(reading.pages.active > 0)
        #expect(reading.pages.wired > 0)

        let physical = KernelReaders.physicalMemory()
        let used = Sampling.memoryUsed(pages: reading.pages, pageSize: reading.pageSize)
        #expect(used.bytes > 0)
        #expect(used.bytes < Int64(physical), "used memory cannot exceed what is installed")

        let pressure = Sampling.memoryPressure(
            pages: reading.pages, pageSize: reading.pageSize, physicalMemory: physical
        )
        #expect(pressure > 0 && pressure < 1)
    }

    @Test("CPU ticks are reported for every core and advance over time")
    func cpuTicksAdvance() async throws {
        let first = try #require(KernelReaders.cpuTicks())
        #expect(first.count == ProcessInfo.processInfo.processorCount)
        #expect(first.allSatisfy { $0.total > 0 })

        try await Task.sleep(for: .milliseconds(120))
        let second = try #require(KernelReaders.cpuTicks())

        // Idle ticks accumulate even on a quiet machine, so the totals must move.
        let advanced = zip(first, second).contains { $1.total > $0.total }
        #expect(advanced, "tick counters should advance between readings")

        let loads = try #require(Sampling.loads(from: first, to: second))
        #expect(loads.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    @Test("Network counters are cumulative and do not go backwards across a short interval")
    func networkCountersAreCumulative() async throws {
        let first = try #require(KernelReaders.networkCounters())
        try await Task.sleep(for: .milliseconds(120))
        let second = try #require(KernelReaders.networkCounters())

        #expect(second.received >= first.received)
        #expect(second.sent >= first.sent)
    }

    @Test("Machine info is populated rather than placeholder text")
    func machineInfoIsPopulated() {
        let machine = KernelReaders.machineInfo()

        #expect(!machine.model.isEmpty)
        #expect(machine.model != "Mac", "should resolve a real model identifier or name")
        #expect(machine.osVersion.hasPrefix("macOS "))
        #expect(machine.processorCoreCount >= 1)
    }

    @Test("Swap usage is readable and non-negative")
    func swapIsRead() {
        #expect(KernelReaders.swapUsed().bytes >= 0)
    }

    @Test("A snapshot fills every card the dashboard shows")
    func snapshotIsComplete() async {
        let snapshot = await LiveSystemMonitor().snapshot()

        #expect(snapshot.disk.total.bytes > 0)
        #expect(snapshot.memory.total.bytes > 0)
        #expect(snapshot.memory.used.bytes > 0)
        #expect(snapshot.cpu.perCore.count == ProcessInfo.processInfo.processorCount
                || snapshot.cpu.perCore.isEmpty, "first sample has no rate yet")
        #expect(!snapshot.machine.model.isEmpty)
    }

    @Test("Streaming produces rising CPU history and stops on cancellation — §8")
    func streamingAccumulatesAndStops() async throws {
        let monitor = LiveSystemMonitor()
        var readings: [SystemSnapshot] = []

        for await snapshot in monitor.stream(interval: .milliseconds(60)) {
            readings.append(snapshot)
            if readings.count >= 4 { break }
        }

        #expect(readings.count == 4)
        // The first sample has no predecessor; later ones do, so history must have grown.
        #expect(readings.last!.cpu.history.count > readings.first!.cpu.history.count)
        #expect(readings.last!.cpu.history.count <= 60)
        #expect(readings.last!.memory.history.count <= 60)
    }

    @Test("Battery is reported on a laptop and absent on a desktop, never garbage")
    func batteryIsPlausibleOrAbsent() {
        guard let battery = KernelReaders.batteryInfo() else {
            // Desktop Mac: absence is the correct answer.
            return
        }
        #expect(battery.charge >= 0 && battery.charge <= 1)
        #expect(battery.health > 0 && battery.health <= 1)
        #expect(battery.cycleCount >= 0)
    }
}

@Suite("Model naming")
struct ModelNameTests {
    @Test("The marketing name is preferred over the hardware identifier")
    func marketingNameIsUsed() {
        let model = KernelReaders.modelName()
        let identifier = KernelReaders.sysctlString("hw.model")

        #expect(!model.isEmpty)
        // "Mac16,8" is the fallback. On any Mac that publishes a product name — which every
        // supported machine does — the dashboard should be showing words, not an identifier.
        if let identifier, model == identifier {
            Issue.record("fell back to the hardware identifier \(identifier)")
        }
        // A marketing name may well contain a comma ("14-inch, Nov 2024"); what must not appear
        // is the identifier shape itself, e.g. "Mac16,8" or "MacBookPro18,3".
        let identifierShape = /^[A-Za-z]+[0-9]+,[0-9]+$/
        #expect(
            model.wholeMatch(of: identifierShape) == nil,
            "\(model) is a hardware identifier, not a model name"
        )
    }

    @Test("The product registry entry is reachable")
    func productEntryIsReachable() {
        let name = KernelReaders.ioRegistryString(path: "IODeviceTree:/product", key: "product-name")
        #expect(name != nil)
    }

    @Test("A nonexistent registry path returns nothing rather than crashing")
    func missingPathIsSafe() {
        #expect(KernelReaders.ioRegistryString(path: "IODeviceTree:/nope", key: "x") == nil)
        #expect(KernelReaders.ioRegistryString(path: "IODeviceTree:/product", key: "nope") == nil)
    }
}
