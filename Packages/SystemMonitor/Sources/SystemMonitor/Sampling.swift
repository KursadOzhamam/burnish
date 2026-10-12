import Foundation
import CoreKit

/// Pure arithmetic behind the live readings.
///
/// The kernel hands out monotonically increasing counters, not rates. Turning those into the
/// percentages and per-second figures the dashboard shows is ordinary arithmetic with awkward
/// edge cases — counter resets, a first sample with nothing to compare against, zero elapsed
/// time — so it lives here, separately from the syscalls, where it can be tested (CLAUDE.md §9).
public enum Sampling {
    /// Per-core CPU tick counters, as reported by `host_processor_info`.
    public struct CPUTicks: Sendable, Hashable {
        public let user: UInt64
        public let system: UInt64
        public let idle: UInt64
        public let nice: UInt64

        public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
            self.user = user
            self.system = system
            self.idle = idle
            self.nice = nice
        }

        public var total: UInt64 { user &+ system &+ idle &+ nice }
        public var busy: UInt64 { user &+ system &+ nice }
    }

    /// Busy fraction between two tick readings, as 0...1.
    ///
    /// Returns nil when there is nothing to measure: the first sample of a session, or two
    /// readings taken so close together that no tick advanced. The caller shows the previous
    /// value rather than a misleading zero.
    public static func load(from previous: CPUTicks, to current: CPUTicks) -> Double? {
        // Counters are monotonic, but a core coming back from sleep can reset them.
        guard current.total >= previous.total, current.busy >= previous.busy else { return nil }

        let totalDelta = current.total - previous.total
        guard totalDelta > 0 else { return nil }

        let busyDelta = current.busy - previous.busy
        return min(1, max(0, Double(busyDelta) / Double(totalDelta)))
    }

    /// Per-core loads, pairing readings by index.
    ///
    /// A core count that changed between samples means the pairing is meaningless, so nothing
    /// is reported rather than something wrong.
    public static func loads(from previous: [CPUTicks], to current: [CPUTicks]) -> [Double]? {
        guard !previous.isEmpty, previous.count == current.count else { return nil }
        let values = zip(previous, current).map { load(from: $0, to: $1) }
        guard values.allSatisfy({ $0 != nil }) else { return nil }
        return values.compactMap { $0 }
    }

    /// Throughput between two cumulative byte counters.
    ///
    /// Interface counters reset when an interface goes down and come back from zero; treating
    /// that as a huge negative — or as a huge positive after wrapping — would spike the chart,
    /// so a decrease is reported as zero rather than guessed at.
    public static func throughput(
        previousBytes: UInt64,
        currentBytes: UInt64,
        elapsed: TimeInterval
    ) -> ByteCount {
        guard elapsed > 0, currentBytes >= previousBytes else { return .zero }
        let delta = Double(currentBytes - previousBytes) / elapsed
        guard delta.isFinite, delta >= 0 else { return .zero }
        return ByteCount(Int64(delta.rounded()))
    }

    /// Memory page counts from `vm_statistics64`.
    public struct MemoryPages: Sendable, Hashable {
        public let active: UInt64
        public let wired: UInt64
        public let compressed: UInt64
        public let free: UInt64
        public let inactive: UInt64
        public let speculative: UInt64

        public init(
            active: UInt64,
            wired: UInt64,
            compressed: UInt64,
            free: UInt64,
            inactive: UInt64,
            speculative: UInt64
        ) {
            self.active = active
            self.wired = wired
            self.compressed = compressed
            self.free = free
            self.inactive = inactive
            self.speculative = speculative
        }
    }

    /// Memory in use, matching what Activity Monitor calls "Memory Used".
    ///
    /// Inactive and speculative pages are excluded: macOS hands those back on demand, and
    /// counting them would tell the user their Mac is fuller than it is — the kind of
    /// inflation §10.4 rules out.
    public static func memoryUsed(pages: MemoryPages, pageSize: UInt64) -> ByteCount {
        ByteCount(Int64(clamping: (pages.active &+ pages.wired &+ pages.compressed) &* pageSize))
    }

    /// Memory pressure as 0...1.
    ///
    /// Derived from the share of physical memory held by pages the system cannot simply drop —
    /// wired and compressed. This tracks the colour of Activity Monitor's pressure graph far
    /// better than "used / total", which sits near 1 on a healthy Mac and would make the health
    /// score permanently pessimistic.
    public static func memoryPressure(
        pages: MemoryPages,
        pageSize: UInt64,
        physicalMemory: UInt64
    ) -> Double {
        guard physicalMemory > 0 else { return 0 }
        let held = Double((pages.wired &+ pages.compressed) &* pageSize)
        return min(1, max(0, held / Double(physicalMemory)))
    }

    /// Appends a sample to a rolling history, keeping the newest `limit` values.
    ///
    /// CLAUDE.md §6.1 shows the last 60 seconds at one sample per second.
    public static func appending(_ value: Double, to history: [Double], limit: Int = 60) -> [Double] {
        guard limit > 0 else { return [] }
        return Array((history + [value]).suffix(limit))
    }
}
