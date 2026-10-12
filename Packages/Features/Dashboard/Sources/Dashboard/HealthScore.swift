import Foundation
import CoreKit
import SystemMonitor

/// The 0–100 figure on the dashboard ring, with its reasoning attached.
///
/// CLAUDE.md §6.1 requires the score to be explainable, and §10.4 forbids making it look worse
/// than the machine is. Two rules follow from that and are enforced by the test suite:
///
/// 1. A healthy machine scores exactly 100. There is no hidden deduction that guarantees the user
///    always has "something to fix".
/// 2. The score *is* the sum of its components — it is not a curve applied afterwards — so the
///    "how was this calculated?" panel can show the real arithmetic.
public struct HealthScore: Sendable, Hashable {
    /// What the score is made of. Weights sum to 100.
    public enum Factor: String, Sendable, Hashable, CaseIterable {
        case freeSpace
        case memoryPressure
        case threats
        case pendingUpdates
        case startupLoad

        /// Points this factor can contribute.
        public var weight: Int {
            switch self {
            case .freeSpace: 30
            case .memoryPressure: 20
            case .threats: 30
            case .pendingUpdates: 10
            case .startupLoad: 10
            }
        }
    }

    /// One factor's contribution, as shown in the explanation panel.
    public struct Component: Sendable, Hashable, Identifiable {
        public let factor: Factor
        /// Points earned, 0...factor.weight.
        public let earned: Int
        /// The measurement this was derived from, shown verbatim to the user.
        public let measurement: String

        public var id: Factor { factor }
        public var available: Int { factor.weight }

        /// 0...1 share of this factor's points earned.
        public var fraction: Double {
            available > 0 ? Double(earned) / Double(available) : 1
        }

        public init(factor: Factor, earned: Int, measurement: String) {
            self.factor = factor
            self.earned = min(factor.weight, max(0, earned))
            self.measurement = measurement
        }
    }

    public let components: [Component]

    /// 0–100. The plain sum of the components.
    public var value: Int {
        components.reduce(0) { $0 + $1.earned }
    }

    /// Factors costing the most points, worst first — the basis for the suggestion cards (§6.1).
    public var weakest: [Component] {
        components
            .filter { $0.earned < $0.available }
            .sorted { ($0.available - $0.earned) > ($1.available - $1.earned) }
    }

    public init(components: [Component]) {
        self.components = components
    }
}

extension HealthScore {
    /// Inputs the score needs beyond a system snapshot.
    ///
    /// Each is optional and absent means "not measured yet": an unmeasured factor awards full
    /// points rather than penalising the user for a scan they have not run (§10.4).
    public struct Inputs: Sendable, Hashable {
        public let threatCount: Int?
        public let pendingUpdateCount: Int?
        public let startupItemCount: Int?

        public init(threatCount: Int? = nil, pendingUpdateCount: Int? = nil, startupItemCount: Int? = nil) {
            self.threatCount = threatCount
            self.pendingUpdateCount = pendingUpdateCount
            self.startupItemCount = startupItemCount
        }

        /// Nothing scanned yet.
        public static let unmeasured = Inputs()
    }

    /// Computes the score from a reading.
    public static func evaluate(snapshot: SystemSnapshot, inputs: Inputs = .unmeasured) -> HealthScore {
        HealthScore(components: [
            freeSpaceComponent(snapshot.disk),
            memoryComponent(snapshot.memory),
            threatComponent(inputs.threatCount),
            updateComponent(inputs.pendingUpdateCount),
            startupComponent(inputs.startupItemCount)
        ])
    }

    /// Full marks at 20% free or more; zero at completely full. Linear in between.
    ///
    /// 20% is the threshold where macOS itself starts struggling, so beyond that extra free space
    /// is not "healthier" and should not earn more points.
    private static func freeSpaceComponent(_ disk: DiskUsage) -> Component {
        let target = 0.20
        let ratio = min(1, disk.freeFraction / target)
        return Component(
            factor: .freeSpace,
            earned: Int((ratio * Double(Factor.freeSpace.weight)).rounded()),
            measurement: "\(disk.free.formatted()) / \(disk.total.formatted())"
        )
    }

    /// Full marks below 0.5 pressure, zero at 0.9 and above.
    private static func memoryComponent(_ memory: MemoryUsage) -> Component {
        let lower = 0.5
        let upper = 0.9
        let ratio: Double = if memory.pressure <= lower {
            1
        } else if memory.pressure >= upper {
            0
        } else {
            1 - (memory.pressure - lower) / (upper - lower)
        }
        return Component(
            factor: .memoryPressure,
            earned: Int((ratio * Double(Factor.memoryPressure.weight)).rounded()),
            measurement: memory.pressure.formatted(.percent.precision(.fractionLength(0)))
        )
    }

    /// Any confirmed threat costs the whole weight. There is no partial credit here: the honest
    /// signal is binary, and §10.3 reserves alarm for real findings.
    private static func threatComponent(_ count: Int?) -> Component {
        guard let count else {
            return Component(factor: .threats, earned: Factor.threats.weight, measurement: "—")
        }
        return Component(
            factor: .threats,
            earned: count == 0 ? Factor.threats.weight : 0,
            measurement: "\(count)"
        )
    }

    /// Two points per pending update, capped at the factor weight.
    private static func updateComponent(_ count: Int?) -> Component {
        guard let count else {
            return Component(
                factor: .pendingUpdates,
                earned: Factor.pendingUpdates.weight,
                measurement: "—"
            )
        }
        return Component(
            factor: .pendingUpdates,
            earned: Factor.pendingUpdates.weight - min(Factor.pendingUpdates.weight, count * 2),
            measurement: "\(count)"
        )
    }

    /// Up to 10 startup items is normal and costs nothing; past that, one point each.
    private static func startupComponent(_ count: Int?) -> Component {
        guard let count else {
            return Component(factor: .startupLoad, earned: Factor.startupLoad.weight, measurement: "—")
        }
        let excess = max(0, count - 10)
        return Component(
            factor: .startupLoad,
            earned: Factor.startupLoad.weight - min(Factor.startupLoad.weight, excess),
            measurement: "\(count)"
        )
    }
}
