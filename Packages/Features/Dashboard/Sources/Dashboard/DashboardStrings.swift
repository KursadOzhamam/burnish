import Foundation
import SystemMonitor

/// Localized text for this feature (CLAUDE.md §15).
enum DashboardStrings {
    private static let bundleURL = Bundle.module.bundleURL

    private static func key(_ value: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(value, bundle: .atURL(bundleURL))
    }

    static let title = key("dashboard.title")
    static let subtitle = key("dashboard.subtitle")
    static let healthTitle = key("dashboard.health.title")
    static let healthExplain = key("dashboard.health.explain")
    static let neverScanned = key("dashboard.health.neverScanned")
    static let scanAction = key("dashboard.scan.action")

    static let disk = key("dashboard.metric.disk")
    static let diskFree = key("dashboard.metric.disk.free")
    static let memory = key("dashboard.metric.memory")
    static let cpu = key("dashboard.metric.cpu")
    static let battery = key("dashboard.metric.battery")
    static let network = key("dashboard.metric.network")

    static let networkDetail = key("dashboard.metric.network.detail")

    static func purgeableNote(_ amount: String) -> LocalizedStringResource {
        key("dashboard.purgeable.note \(amount)")
    }

    static func diskDetail(total: String) -> LocalizedStringResource {
        key("dashboard.metric.disk.detail \(total)")
    }

    static func points(earned: Int, available: Int) -> LocalizedStringResource {
        key("dashboard.score.points \(earned) \(available)")
    }

    static func name(for factor: HealthScore.Factor) -> LocalizedStringResource {
        switch factor {
        case .freeSpace: key("dashboard.factor.freeSpace")
        case .memoryPressure: key("dashboard.factor.memoryPressure")
        case .threats: key("dashboard.factor.threats")
        case .pendingUpdates: key("dashboard.factor.pendingUpdates")
        case .startupLoad: key("dashboard.factor.startupLoad")
        }
    }

    static let recTitle = key("dashboard.rec.title")
    static let recOpen = key("dashboard.rec.open")

    static func text(for kind: Recommendation.Kind) -> LocalizedStringResource {
        switch kind {
        case .cleanable(let name, let size): LocalizedStringResource("dashboard.rec.cleanable \(name) \(size.formatted())", bundle: .atURL(bundleURL))
        case .threats(let count): LocalizedStringResource("dashboard.rec.threats \(count)", bundle: .atURL(bundleURL))
        case .lowDisk(let free): LocalizedStringResource("dashboard.rec.lowDisk \(free.formatted())", bundle: .atURL(bundleURL))
        case .manyStartupItems(let count): LocalizedStringResource("dashboard.rec.startup \(count)", bundle: .atURL(bundleURL))
        }
    }
}
