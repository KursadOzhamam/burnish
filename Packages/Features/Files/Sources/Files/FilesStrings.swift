import Foundation

/// Localized text for this feature (CLAUDE.md §15).
enum FilesStrings {
    private static let bundleURL = Bundle.module.bundleURL

    static func key(_ value: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(value), bundle: .atURL(bundleURL))
    }

    static let title = key("files.title")
    static let subtitle = key("files.subtitle")
    static let scan = key("files.action.scan")
    static let cancel = key("files.action.cancel")
    static let trash = key("files.action.trash")
    static let rescan = key("files.action.rescan")
    static let emptyTitle = key("files.empty.title")
    static let emptyDetail = key("files.empty.detail")
    static let partial = key("files.partial")
    static let permission = key("files.permission")
    static let kindFilter = key("files.filter.kind")
    static let ageFilter = key("files.filter.age")
    static let allKinds = key("files.filter.kind.all")
    static let cloud = key("files.cloud")

    static func kind(_ kind: FileKind) -> LocalizedStringResource {
        key("files.kind.\(kind.rawValue)")
    }

    static func age(_ filter: LargeFilesModel.AgeFilter) -> LocalizedStringResource {
        switch filter {
        case .any: key("files.age.any")
        case .over90Days: key("files.age.90")
        case .overOneYear: key("files.age.365")
        }
    }

    static func selected(count: Int, size: String) -> LocalizedStringResource {
        LocalizedStringResource("files.selected \(count) \(size)", bundle: .atURL(bundleURL))
    }

    static func found(count: Int) -> LocalizedStringResource {
        LocalizedStringResource("files.found \(count)", bundle: .atURL(bundleURL))
    }

    static func remaining(_ text: String) -> LocalizedStringResource {
        LocalizedStringResource("files.remaining \(text)", bundle: .atURL(bundleURL))
    }

    static func unused(days: Int) -> LocalizedStringResource {
        LocalizedStringResource("files.unused \(days)", bundle: .atURL(bundleURL))
    }
}
