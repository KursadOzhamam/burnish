import Foundation
import Darwin

/// One running process, as seen at an instant.
public struct ProcessSample: Identifiable, Sendable, Hashable {
    public let pid: Int32
    public let name: String
    public let path: String?
    public let userID: UInt32
    public let residentBytes: UInt64
    /// CPU time used so far, in nanoseconds.
    public let cpuTimeNanoseconds: UInt64

    public var id: Int32 { pid }

    /// Something macOS runs for itself: root's, or from a system folder. Never offered to quit.
    public var isSystem: Bool {
        if userID == 0 { return true }
        guard let path else { return false }
        return ["/System/", "/usr/", "/sbin/", "/bin/", "/Library/Apple/", "/private/var/db/"].contains { path.hasPrefix($0) }
    }
}

/// A process with its CPU share over the sampling interval.
public struct ProcessLoad: Identifiable, Sendable, Hashable {
    public let sample: ProcessSample
    /// Share of one core, so 100 is a full core and 250 is two and a half.
    public let cpuPercent: Double

    public var id: Int32 { sample.pid }
}

/// Reads the process table with `libproc`. Reads only.
public struct ProcessSampler: Sendable {
    public init() {}

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private static func string(from buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Every process the user may inspect.
    public func sample() -> [ProcessSample] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(capacity) + 16)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard count > 0 else { return [] }

        var result: [ProcessSample] = []
        for pid in pids.prefix(Int(count)) where pid > 0 {
            var task = proc_taskinfo()
            let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, taskSize) == taskSize else { continue }

            var bsd = proc_bsdinfo()
            let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            let uid = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) == bsdSize ? bsd.pbi_uid : 0

            var nameBuffer = [CChar](repeating: 0, count: 256)
            proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            var pathBuffer = [CChar](repeating: 0, count: 4_096)
            let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))

            let ticks = task.pti_total_user + task.pti_total_system
            let nanoseconds = ticks * UInt64(Self.timebase.numer) / UInt64(max(1, Self.timebase.denom))
            result.append(
                ProcessSample(
                    pid: pid,
                    name: Self.string(from: nameBuffer),
                    path: pathLength > 0 ? Self.string(from: pathBuffer) : nil,
                    userID: uid,
                    residentBytes: task.pti_resident_size,
                    cpuTimeNanoseconds: nanoseconds
                )
            )
        }
        return result
    }

    /// CPU share per process over `interval` seconds.
    public func load(over interval: TimeInterval = 1) async -> [ProcessLoad] {
        let first = sample()
        let started = Date()
        try? await Task.sleep(for: .seconds(interval))
        let second = sample()
        let elapsed = max(0.001, Date().timeIntervalSince(started))
        let before = Dictionary(first.map { ($0.pid, $0.cpuTimeNanoseconds) }, uniquingKeysWith: { $1 })
        return second.map { now in
            let used = now.cpuTimeNanoseconds >= (before[now.pid] ?? now.cpuTimeNanoseconds)
                ? now.cpuTimeNanoseconds - (before[now.pid] ?? now.cpuTimeNanoseconds) : 0
            return ProcessLoad(sample: now, cpuPercent: Double(used) / 1_000_000_000 / elapsed * 100)
        }
    }

    public static func topByMemory(_ samples: [ProcessSample], count: Int = 10) -> [ProcessSample] {
        Array(samples.sorted { $0.residentBytes > $1.residentBytes }.prefix(count))
    }

    public static func topByCPU(_ loads: [ProcessLoad], count: Int = 10) -> [ProcessLoad] {
        Array(loads.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(count))
    }
}
