import Foundation
import ScanEngine

/// Localized text for the shared deletion screens (CLAUDE.md §15).
enum DeletionStrings {
    private static let bundleURL = Bundle.module.bundleURL

    static func key(_ value: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(value), bundle: .atURL(bundleURL))
    }

    static let title = key("deletion.confirm.title")
    static let note = key("deletion.confirm.note")
    static let permanentWarning = key("deletion.confirm.permanentWarning")
    static let moveToTrash = key("deletion.confirm.moveToTrash")
    static let deletePermanently = key("deletion.confirm.deletePermanently")
    static let noHistory = key("deletion.confirm.noHistory")
    static let resultTitle = key("deletion.result.title")
    static let done = key("deletion.result.done")
    static let cancel = key("deletion.cancel")

    static func summary(count: Int, size: String) -> LocalizedStringResource {
        LocalizedStringResource("deletion.summary \(count) \(size)", bundle: .atURL(bundleURL))
    }

    static func failures(count: Int) -> LocalizedStringResource {
        LocalizedStringResource("deletion.result.failures \(count)", bundle: .atURL(bundleURL))
    }

    /// Plain-language reason an item was left alone.
    static func reason(for blocked: ScanItem.BlockedReason) -> LocalizedStringResource {
        switch blocked {
        case .needsHelper: key("deletion.blocked.needsHelper")
        case .ownerRunning: key("deletion.blocked.ownerRunning")
        case .protectedPath: key("deletion.blocked.protectedPath")
        case .nestedInAnotherItem: key("deletion.blocked.nested")
        case .outsideScope, .excludedByUser, .needsFullDiskAccess: key("deletion.blocked.other")
        }
    }
}
