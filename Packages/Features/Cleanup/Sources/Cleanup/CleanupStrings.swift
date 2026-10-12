import Foundation
import ScanEngine

/// Localized text for this feature (CLAUDE.md §15).
enum CleanupStrings {
    private static let bundleURL = Bundle.module.bundleURL

    static func key(_ value: String) -> LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(value),
            bundle: .atURL(bundleURL)
        )
    }

    static let title = key("cleanup.title")
    static let subtitle = key("cleanup.subtitle")
    static let scanAction = key("cleanup.action.scan")
    static let reviewAction = key("cleanup.action.review")
    static let cancel = key("cleanup.action.cancel")
    static let selectAll = key("cleanup.action.selectAll")
    static let deselectAll = key("cleanup.action.deselectAll")
    static let nothingFound = key("cleanup.empty.title")
    static let nothingFoundDetail = key("cleanup.empty.detail")
    static let needsHelper = key("cleanup.blocked.needsHelper")
    static let ownerRunning = key("cleanup.blocked.ownerRunning")
    static let permissionRequired = key("cleanup.permission.required")
    static let permissionBanner = key("cleanup.permission.banner")
    static let permissionOpen = key("cleanup.permission.open")
    static let unreadableFolder = key("cleanup.permission.unreadable")
    static let protectedPath = key("cleanup.blocked.protectedPath")
    static let nested = key("cleanup.blocked.nested")
    static let otherBlocked = key("cleanup.blocked.other")

    static func summary(count: Int, size: String) -> LocalizedStringResource {
        LocalizedStringResource("cleanup.summary \(count) \(size)", bundle: .atURL(bundleURL))
    }

    static func selected(count: Int, size: String) -> LocalizedStringResource {
        LocalizedStringResource("cleanup.selected \(count) \(size)", bundle: .atURL(bundleURL))
    }

    static func skipped(count: Int) -> LocalizedStringResource {
        LocalizedStringResource("cleanup.skipped \(count)", bundle: .atURL(bundleURL))
    }

    static func failures(count: Int) -> LocalizedStringResource {
        LocalizedStringResource("cleanup.result.failures \(count)", bundle: .atURL(bundleURL))
    }

    /// Plain-language reason an item was left alone.
    static func reason(for blocked: ScanItem.BlockedReason) -> LocalizedStringResource {
        switch blocked {
        case .needsHelper: needsHelper
        case .ownerRunning: ownerRunning
        case .protectedPath: protectedPath
        case .nestedInAnotherItem: nested
        case .outsideScope, .excludedByUser, .needsFullDiskAccess: otherBlocked
        }
    }
}
