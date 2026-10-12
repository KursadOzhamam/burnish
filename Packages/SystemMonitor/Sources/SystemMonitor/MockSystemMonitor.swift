import Foundation
import CoreKit

/// Plausible fake readings for Phase 1, previews and tests.
///
/// Values drift smoothly rather than jumping randomly so the live charts and counters can be
/// judged honestly while the real readers are still missing (Phase 3).
public struct MockSystemMonitor: SystemMonitoring {
    private let seed: SystemSnapshot

    public init(seed: SystemSnapshot = .sample) {
        self.seed = seed
    }

    public func snapshot() async -> SystemSnapshot {
        seed
    }

    public func stream(interval: Duration) -> AsyncStream<SystemSnapshot> {
        AsyncStream { continuation in
            let task = Task {
                var cpuHistory = seed.cpu.history
                var memoryHistory = seed.memory.history
                var cpu = seed.cpu.total
                var pressure = seed.memory.pressure

                while !Task.isCancelled {
                    // Random walk, clamped, so the sparkline looks like a real trace.
                    cpu = min(0.95, max(0.03, cpu + .random(in: -0.07...0.07)))
                    pressure = min(0.9, max(0.1, pressure + .random(in: -0.03...0.03)))

                    cpuHistory = (cpuHistory + [cpu]).suffix(60)
                    memoryHistory = (memoryHistory + [pressure]).suffix(60)

                    continuation.yield(
                        SystemSnapshot(
                            machine: seed.machine,
                            disk: seed.disk,
                            memory: MemoryUsage(
                                total: seed.memory.total,
                                used: seed.memory.used,
                                compressed: seed.memory.compressed,
                                swapUsed: seed.memory.swapUsed,
                                pressure: pressure,
                                history: Array(memoryHistory)
                            ),
                            cpu: CPULoad(
                                total: cpu,
                                perCore: seed.cpu.perCore.map {
                                    min(1, max(0, $0 + .random(in: -0.12...0.12)))
                                },
                                history: Array(cpuHistory)
                            ),
                            battery: seed.battery,
                            network: NetworkThroughput(
                                download: .megabytes(Int64.random(in: 0...18)),
                                upload: .megabytes(Int64.random(in: 0...4))
                            )
                        )
                    )

                    try? await Task.sleep(for: interval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension SystemSnapshot {
    /// Fixed sample used by previews and tests.
    public static let sample = SystemSnapshot(
        machine: MachineInfo(
            model: "MacBook Pro (14-inch)",
            osVersion: "macOS 27.0",
            processorCoreCount: 10
        ),
        disk: DiskUsage(
            total: .gigabytes(1_000),
            free: .gigabytes(214),
            purgeable: .gigabytes(31),
            reclaimable: .gigabytes(42)
        ),
        memory: MemoryUsage(
            total: .gigabytes(18),
            used: .gigabytes(11),
            compressed: .gigabytes(3),
            swapUsed: .gigabytes(1),
            pressure: 0.42,
            history: (0..<60).map { 0.4 + 0.1 * sin(Double($0) / 7) }
        ),
        cpu: CPULoad(
            total: 0.23,
            perCore: [0.31, 0.12, 0.44, 0.08, 0.19, 0.27, 0.05, 0.11, 0.38, 0.14],
            history: (0..<60).map { 0.25 + 0.12 * sin(Double($0) / 5) }
        ),
        battery: BatteryInfo(charge: 0.76, health: 0.91, cycleCount: 214, isCharging: false),
        network: NetworkThroughput(download: .megabytes(4), upload: .megabytes(1))
    )
}
