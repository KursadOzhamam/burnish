import Foundation

/// Localized text for this feature (CLAUDE.md §15).
enum SmartScanStrings {
    private static let bundleURL = Bundle.module.bundleURL

    private static func key(_ value: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(value, bundle: .atURL(bundleURL))
    }

    static let title = key("smartscan.title")
    static let subtitle = key("smartscan.subtitle")
    static let idleAction = key("smartscan.idle.action")
    static let cancel = key("smartscan.cancel")
    static let found = key("smartscan.found")
    static let finishedTitle = key("smartscan.finished.title")
    static let finishedNote = key("smartscan.finished.note")
    static let cancelled = key("smartscan.cancelled")
    static let heavyHint = key("smartscan.heavy.hint")
    static let ready = key("smartscan.ready")
    static let review = key("smartscan.review")
    static let rescan = key("smartscan.rescan")
    static let permission = key("smartscan.permission")

    static func additional(_ size: String) -> LocalizedStringResource {
        key("smartscan.additional \(size)")
    }

    static func itemsFound(_ count: Int) -> LocalizedStringResource {
        key("smartscan.itemsFound \(count)")
    }
}
