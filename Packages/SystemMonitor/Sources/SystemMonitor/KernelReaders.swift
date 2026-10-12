import Foundation
import Darwin
import CoreKit

/// Thin wrappers over the kernel interfaces.
///
/// Each function does one syscall and converts the result; the arithmetic lives in `Sampling`
/// where it is tested. Every one of these returns an optional rather than trapping: a reading
/// that cannot be taken is a missing number on a card, never a crash in an app that deletes
/// files.
enum KernelReaders {

    // MARK: CPU

    /// Per-core tick counters from `host_processor_info`.
    static func cpuTicks() -> [Sampling.CPUTicks]? {
        var coreCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &coreCount,
            &info,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info else { return nil }

        // host_processor_info allocates; the deallocation is ours.
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: info)),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(coreCount)).map { core in
            let base = core * stride
            return Sampling.CPUTicks(
                user: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])),
                system: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])),
                idle: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])),
                nice: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            )
        }
    }

    // MARK: Memory

    static func memoryPages() -> (pages: Sampling.MemoryPages, pageSize: UInt64)? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pages = Sampling.MemoryPages(
            active: UInt64(stats.active_count),
            wired: UInt64(stats.wire_count),
            compressed: UInt64(stats.compressor_page_count),
            free: UInt64(stats.free_count),
            inactive: UInt64(stats.inactive_count),
            speculative: UInt64(stats.speculative_count)
        )
        return (pages, pageSize())
    }

    /// Kernel page size.
    ///
    /// Read through `host_page_size` rather than the `vm_kernel_page_size` global, which Swift 6
    /// rejects as shared mutable state.
    static func pageSize() -> UInt64 {
        var size: vm_size_t = 0
        guard host_page_size(mach_host_self(), &size) == KERN_SUCCESS else {
            return UInt64(sysconf(_SC_PAGESIZE))
        }
        return UInt64(size)
    }

    /// Swap in use, from `vm.swapusage`.
    static func swapUsed() -> ByteCount {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return .zero }
        return ByteCount(Int64(clamping: usage.xsu_used))
    }

    // MARK: Disk

    /// Capacity of the volume containing `url`.
    ///
    /// `volumeAvailableCapacityForImportantUsage` includes space macOS would purge on demand,
    /// while `volumeAvailableCapacity` is what is free right now. The difference is the
    /// purgeable figure the dashboard shows separately and never counts as a cleanup gain (§10.4).
    static func diskUsage(for url: URL = URL(fileURLWithPath: "/")) -> DiskUsage? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity
        else { return nil }

        let free = Int64(values.volumeAvailableCapacity ?? 0)
        let important = values.volumeAvailableCapacityForImportantUsage ?? Int64(free)
        let purgeable = max(0, important - free)

        return DiskUsage(
            total: ByteCount(Int64(total)),
            free: ByteCount(free),
            purgeable: ByteCount(purgeable)
        )
    }

    // MARK: Network

    /// Cumulative bytes in and out across physical interfaces.
    ///
    /// Loopback is excluded: local traffic is not network activity the user cares about.
    static func networkCounters() -> (received: UInt64, sent: UInt64)? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }

        var received: UInt64 = 0
        var sent: UInt64 = 0

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }
            guard (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            guard let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }

            received &+= UInt64(data.pointee.ifi_ibytes)
            sent &+= UInt64(data.pointee.ifi_obytes)
        }

        return (received, sent)
    }

    // MARK: Machine

    static func machineInfo() -> MachineInfo {
        MachineInfo(
            model: modelName(),
            osVersion: "macOS " + ProcessInfo.processInfo.operatingSystemVersion.shortDescription,
            processorCoreCount: ProcessInfo.processInfo.processorCount
        )
    }

    /// Human-readable model, e.g. "MacBook Pro (14-inch, Nov 2024)".
    ///
    /// Read from `IODeviceTree:/product`, which carries the marketing name. Falls back to the
    /// hardware identifier ("Mac16,8") rather than guessing: a wrong model on the dashboard
    /// would undermine trust in every other number on it.
    static func modelName() -> String {
        if let name = ioRegistryString(path: "IODeviceTree:/product", key: "product-name") {
            return name
        }
        if let name = ioRegistryString(path: "IODeviceTree:/product", key: "product-description") {
            return name
        }
        return sysctlString("hw.model") ?? "Mac"
    }

    static func physicalMemory() -> UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    // MARK: sysctl helpers

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}

extension OperatingSystemVersion {
    /// "27.0.1", trimming a zero patch component the way macOS itself does.
    var shortDescription: String {
        patchVersion == 0
            ? "\(majorVersion).\(minorVersion)"
            : "\(majorVersion).\(minorVersion).\(patchVersion)"
    }
}
