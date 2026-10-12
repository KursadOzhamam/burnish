import Foundation
import CoreKit

/// One reading of the machine's state.
///
/// Published at most once a second and only while a view that shows it is on screen
/// (CLAUDE.md §8).
public struct SystemSnapshot: Sendable, Hashable {
    public let machine: MachineInfo
    public let disk: DiskUsage
    public let memory: MemoryUsage
    public let cpu: CPULoad
    public let battery: BatteryInfo?
    public let network: NetworkThroughput
    public let capturedAt: Date

    public init(
        machine: MachineInfo,
        disk: DiskUsage,
        memory: MemoryUsage,
        cpu: CPULoad,
        battery: BatteryInfo?,
        network: NetworkThroughput,
        capturedAt: Date = .now
    ) {
        self.machine = machine
        self.disk = disk
        self.memory = memory
        self.cpu = cpu
        self.battery = battery
        self.network = network
        self.capturedAt = capturedAt
    }
}

public struct MachineInfo: Sendable, Hashable {
    /// Marketing model name, e.g. "MacBook Pro (14-inch, M3)".
    public let model: String
    /// e.g. "macOS 27.0.1".
    public let osVersion: String
    public let processorCoreCount: Int

    public init(model: String, osVersion: String, processorCoreCount: Int) {
        self.model = model
        self.osVersion = osVersion
        self.processorCoreCount = max(1, processorCoreCount)
    }
}

public struct DiskUsage: Sendable, Hashable {
    public let total: ByteCount
    public let free: ByteCount

    /// Space macOS reports as purgeable — it can be reclaimed by the system on demand.
    ///
    /// CLAUDE.md §10.4: this is shown separately and never counted as a cleanup gain, because
    /// the user did not gain it and we did not free it.
    public let purgeable: ByteCount

    /// What Burnish believes it could actually clean, from the last scan. Nil until a scan runs —
    /// deliberately not guessed, so the dashboard cannot imply a number it has not measured.
    public let reclaimable: ByteCount?

    public init(total: ByteCount, free: ByteCount, purgeable: ByteCount, reclaimable: ByteCount? = nil) {
        self.total = total
        self.free = free
        self.purgeable = purgeable
        self.reclaimable = reclaimable
    }

    public var used: ByteCount { total - free }

    /// 0...1 share of the volume in use.
    public var usedFraction: Double { used.fraction(of: total) }

    /// 0...1 share free. Feeds the health score.
    public var freeFraction: Double { free.fraction(of: total) }
}

public struct MemoryUsage: Sendable, Hashable {
    public let total: ByteCount
    public let used: ByteCount
    public let compressed: ByteCount
    public let swapUsed: ByteCount

    /// 0...1, as reported by the kernel. Above ~0.75 the machine is genuinely struggling.
    public let pressure: Double

    /// Most recent samples, oldest first, for the sparkline (last 60 s per §6.1).
    public let history: [Double]

    public init(
        total: ByteCount,
        used: ByteCount,
        compressed: ByteCount,
        swapUsed: ByteCount,
        pressure: Double,
        history: [Double] = []
    ) {
        self.total = total
        self.used = used
        self.compressed = compressed
        self.swapUsed = swapUsed
        self.pressure = min(1, max(0, pressure))
        self.history = history
    }

    public var usedFraction: Double { used.fraction(of: total) }
}

public struct CPULoad: Sendable, Hashable {
    /// 0...1 total load across all cores.
    public let total: Double
    /// 0...1 per core.
    public let perCore: [Double]
    /// Recent total-load samples for the sparkline.
    public let history: [Double]

    public init(total: Double, perCore: [Double], history: [Double] = []) {
        self.total = min(1, max(0, total))
        self.perCore = perCore.map { min(1, max(0, $0)) }
        self.history = history
    }
}

public struct BatteryInfo: Sendable, Hashable {
    /// 0...1 current charge.
    public let charge: Double
    /// 0...1 maximum capacity relative to design capacity.
    public let health: Double
    public let cycleCount: Int
    public let isCharging: Bool

    public init(charge: Double, health: Double, cycleCount: Int, isCharging: Bool) {
        self.charge = min(1, max(0, charge))
        self.health = min(1, max(0, health))
        self.cycleCount = max(0, cycleCount)
        self.isCharging = isCharging
    }
}

public struct NetworkThroughput: Sendable, Hashable {
    /// Bytes per second.
    public let download: ByteCount
    public let upload: ByteCount

    public init(download: ByteCount, upload: ByteCount) {
        self.download = download
        self.upload = upload
    }
}
