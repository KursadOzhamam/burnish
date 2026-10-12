import Foundation
import SafetyKit
import SafetyKitMac

/// Localized text for this feature (CLAUDE.md §15).
enum HistoryStrings {
    private static let bundleURL = Bundle.module.bundleURL

    static func key(_ value: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(value, bundle: .atURL(bundleURL))
    }

    static let title = key("history.title")
    static let subtitle = key("history.subtitle")
    static let empty = key("history.empty")
    static let unavailable = key("history.unavailable")
    static let restore = key("history.restore")
    static let close = key("history.close")
    static let restoredBadge = key("history.badge.restored")

    static func reclaimed(_ size: String) -> LocalizedStringResource {
        key("history.reclaimed \(size)")
    }

    static func restored(_ name: String) -> LocalizedStringResource {
        key("history.notice.restored \(name)")
    }

    static func outcome(_ outcome: OperationRecord.Outcome) -> LocalizedStringResource {
        switch outcome {
        case .trashed: key("history.outcome.trashed")
        case .deleted: key("history.outcome.deleted")
        case .skipped: key("history.outcome.skipped")
        case .failed: key("history.outcome.failed")
        }
    }

    static func message(for failure: RestoreService.Failure) -> LocalizedStringResource {
        switch failure {
        case .unknownRecord, .notRestorable: key("history.failure.notRestorable")
        case .missingFromTrash: key("history.failure.missingFromTrash")
        case .destinationOccupied: key("history.failure.destinationOccupied")
        case .moveFailed: key("history.failure.moveFailed")
        }
    }
}
