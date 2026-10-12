import Foundation
import CoreKit

/// Real readings from the running machine.
///
/// CPU load and network throughput are rates, so each needs the previous sample to compute.
/// That state lives in an actor, which is what lets the monitor stay `Sendable` and be shared
/// between the dashboard and the menu bar panel without a lock (CLAUDE.md §2).
///
/// CLAUDE.md §8 governs the cadence: one reading a second, only while something is watching.
/// The stream stops as soon as its task is cancelled.
public struct LiveSystemMonitor: SystemMonitoring {
    private let state = SampleState()
    private let volume: URL

    /// - Parameter volume: which volume to report. Defaults to the boot volume.
    public init(volume: URL = URL(fileURLWithPath: "/")) {
        self.volume = volume
    }

    public func snapshot() async -> SystemSnapshot {
        await read()
    }

    public func stream(interval: Duration = .seconds(1)) -> AsyncStream<SystemSnapshot> {
        AsyncStream { continuation in
            let task = Task {
                // The first reading has no predecessor, so rates come back as zero. Take one
                // immediately anyway: an empty dashboard for a whole second looks broken.
                continuation.yield(await read())

                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    guard !Task.isCancelled else { break }
                    continuation.yield(await read())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func read() async -> SystemSnapshot {
        let now = Date()
        let cpu = await state.cpu(at: now)
        let network = await state.network(at: now)

        let memory = Self.readMemory()
        let memoryHistory = await state.memoryHistory(appending: memory.pressure)

        return SystemSnapshot(
            machine: KernelReaders.machineInfo(),
            disk: KernelReaders.diskUsage(for: volume) ?? .unavailable,
            memory: MemoryUsage(
                total: memory.total,
                used: memory.used,
                compressed: memory.compressed,
                swapUsed: memory.swapUsed,
                pressure: memory.pressure,
                history: memoryHistory
            ),
            cpu: cpu,
            battery: KernelReaders.batteryInfo(),
            network: network,
            capturedAt: now
        )
    }

    /// One memory reading, before it is paired with the rolling history.
    private struct MemoryReading {
        let total: ByteCount
        let used: ByteCount
        let compressed: ByteCount
        let swapUsed: ByteCount
        let pressure: Double
    }

    private static func readMemory() -> MemoryReading {
        let physical = KernelReaders.physicalMemory()
        let total = ByteCount(Int64(clamping: physical))

        guard let reading = KernelReaders.memoryPages() else {
            // The card shows installed memory and nothing else rather than inventing figures.
            return MemoryReading(
                total: total, used: .zero, compressed: .zero, swapUsed: .zero, pressure: 0
            )
        }

        return MemoryReading(
            total: total,
            used: Sampling.memoryUsed(pages: reading.pages, pageSize: reading.pageSize),
            compressed: ByteCount(Int64(clamping: reading.pages.compressed &* reading.pageSize)),
            swapUsed: KernelReaders.swapUsed(),
            pressure: Sampling.memoryPressure(
                pages: reading.pages,
                pageSize: reading.pageSize,
                physicalMemory: physical
            )
        )
    }
}

/// Holds the previous sample so rates can be derived.
private actor SampleState {
    private var previousTicks: [Sampling.CPUTicks] = []
    private var previousNetwork: (received: UInt64, sent: UInt64)?
    private var previousNetworkAt: Date?
    private var cpuHistory: [Double] = []
    private var memoryHistoryValues: [Double] = []
    private var lastLoad: Double = 0
    private var lastPerCore: [Double] = []

    func cpu(at _: Date) -> CPULoad {
        guard let current = KernelReaders.cpuTicks() else {
            return CPULoad(total: lastLoad, perCore: lastPerCore, history: cpuHistory)
        }

        defer { previousTicks = current }

        guard let perCore = Sampling.loads(from: previousTicks, to: current) else {
            // First sample, or the counters moved in a way we cannot interpret. Report the
            // previous figures rather than a zero that would dent the chart.
            return CPULoad(total: lastLoad, perCore: lastPerCore, history: cpuHistory)
        }

        let total = perCore.isEmpty ? 0 : perCore.reduce(0, +) / Double(perCore.count)
        lastLoad = total
        lastPerCore = perCore
        cpuHistory = Sampling.appending(total, to: cpuHistory)

        return CPULoad(total: total, perCore: perCore, history: cpuHistory)
    }

    func network(at date: Date) -> NetworkThroughput {
        guard let current = KernelReaders.networkCounters() else {
            return NetworkThroughput(download: .zero, upload: .zero)
        }
        defer {
            previousNetwork = current
            previousNetworkAt = date
        }

        guard let previous = previousNetwork, let previousAt = previousNetworkAt else {
            return NetworkThroughput(download: .zero, upload: .zero)
        }

        let elapsed = date.timeIntervalSince(previousAt)
        return NetworkThroughput(
            download: Sampling.throughput(
                previousBytes: previous.received, currentBytes: current.received, elapsed: elapsed
            ),
            upload: Sampling.throughput(
                previousBytes: previous.sent, currentBytes: current.sent, elapsed: elapsed
            )
        )
    }

    /// Returns the pressure history, optionally appending a new sample first.
    func memoryHistory(appending value: Double?) -> [Double] {
        if let value {
            memoryHistoryValues = Sampling.appending(value, to: memoryHistoryValues)
        }
        return memoryHistoryValues
    }
}

extension DiskUsage {
    /// Shown when the volume cannot be read — all zeroes, so the card reads as unavailable
    /// rather than as an empty disk.
    static let unavailable = DiskUsage(total: .zero, free: .zero, purgeable: .zero)
}
