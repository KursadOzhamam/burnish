import Foundation

/// Localized text for this feature (CLAUDE.md §15).
enum AppsStrings {
    private static let bundleURL = Bundle.module.bundleURL

    static func key(_ value: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(value), bundle: .atURL(bundleURL))
    }

    static let title = key("apps.title")
    static let subtitle = key("apps.subtitle")
    static let tabApps = key("apps.tab.apps")
    static let tabExtensions = key("apps.tab.extensions")
    static let extensionsSubtitle = key("apps.extensions.subtitle")
    static let extensionsScan = key("apps.extensions.scan")
    static let extensionsNone = key("apps.extensions.none")
    static let reset = key("apps.reset")
    static let updateStore = key("apps.update.store")
    static let updateOwn = key("apps.update.own")
    static let updateNote = key("apps.update.note")
    static let tabOrphans = key("apps.tab.orphans")
    static let search = key("apps.search")
    static let sortName = key("apps.sort.name")
    static let sortSize = key("apps.sort.size")
    static let sortLastUsed = key("apps.sort.lastUsed")
    static let sort = key("apps.sort")
    static let unused = key("apps.unused")
    static let showApple = key("apps.showApple")
    static let uninstall = key("apps.uninstall")
    static let loading = key("apps.loading")
    static let empty = key("apps.empty")
    static let neverOpened = key("apps.neverOpened")
    static let apple = key("apps.apple")
    static let running = key("apps.running")
    static let quit = key("apps.quit")
    static let runningNote = key("apps.runningNote")
    static let reviewTitle = key("apps.review.title")
    static let reviewApp = key("apps.review.app")
    static let reviewLeftovers = key("apps.review.leftovers")
    static let reviewNone = key("apps.review.none")
    static let reviewLowNote = key("apps.review.lowNote")
    static let reviewCancel = key("apps.review.cancel")
    static let reviewTrash = key("apps.review.trash")
    static let reviewLoading = key("apps.review.loading")
    static let orphansSubtitle = key("apps.orphans.subtitle")
    static let orphansScan = key("apps.orphans.scan")
    static let orphansNone = key("apps.orphans.none")
    static let orphansTrash = key("apps.orphans.trash")
    static let done = key("apps.done")

    static func count(_ n: Int) -> LocalizedStringResource {
        LocalizedStringResource("apps.count \(n)", bundle: .atURL(bundleURL))
    }
    static func selected(count: Int, size: String) -> LocalizedStringResource {
        LocalizedStringResource("apps.selected \(count) \(size)", bundle: .atURL(bundleURL))
    }
    static func lastUsed(days: Int) -> LocalizedStringResource {
        LocalizedStringResource("apps.lastUsed \(days)", bundle: .atURL(bundleURL))
    }
    static func orphansFound(count: Int, size: String) -> LocalizedStringResource {
        LocalizedStringResource("apps.orphans.found \(count) \(size)", bundle: .atURL(bundleURL))
    }
}
