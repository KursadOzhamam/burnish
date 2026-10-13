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
    static let hubLarge = key("files.hub.large")
    static let hubMap = key("files.hub.map")
    static let scopeButton = key("files.scope.button")
    static let scopeTitle = key("files.scope.title")
    static let scopeSubtitle = key("files.scope.subtitle")
    static let scopeAddFolder = key("files.scope.addFolder")
    static let scopeAddVolume = key("files.scope.addVolume")
    static let scopeNoVolumes = key("files.scope.noVolumes")
    static let scopeExcluded = key("files.scope.excluded")
    static let scopeExclude = key("files.scope.exclude")
    static let scopeNoneExcluded = key("files.scope.noneExcluded")
    static let scopeDone = key("files.scope.done")
    static let scopeRemove = key("files.scope.remove")
    static let mapRoot = key("files.map.root")
    static let mapHome = key("files.map.home")
    static let hubSimilar = key("files.hub.similar")
    static let similarTitle = key("files.similar.title")
    static let similarSubtitle = key("files.similar.subtitle")
    static let similarEmptyTitle = key("files.similar.empty.title")
    static let similarEmptyDetail = key("files.similar.empty.detail")
    static let keepLargest = key("files.dup.keepLargest")
    static let hubShredder = key("files.hub.shredder")
    static let shredTitle = key("files.shred.title")
    static let shredSubtitle = key("files.shred.subtitle")
    static let shredAdd = key("files.shred.add")
    static let shredDrop = key("files.shred.drop")
    static let shredHonest = key("files.shred.honest")
    static let shredAcknowledge = key("files.shred.acknowledge")
    static let shredDelete = key("files.shred.delete")
    static let shredBlocked = key("files.shred.blocked")
    static let shredRemove = key("files.shred.remove")
    static let shredClear = key("files.shred.clear")
    static let fdaNotice = key("files.fda.notice")
    static let fdaOpen = key("files.fda.open")
    static let hubDuplicates = key("files.hub.duplicates")
    static let dupTitle = key("files.dup.title")
    static let dupSubtitle = key("files.dup.subtitle")
    static let dupEmptyTitle = key("files.dup.empty.title")
    static let dupEmptyDetail = key("files.dup.empty.detail")
    static let keepOldest = key("files.dup.keepOldest")
    static let keepShortest = key("files.dup.keepShortest")
    static let clearSelection = key("files.dup.clear")
    static let keepNote = key("files.dup.keepNote")

    static func reclaimable(_ size: String) -> LocalizedStringResource {
        LocalizedStringResource("files.dup.reclaimable \(size)", bundle: .atURL(bundleURL))
    }

    static func copies(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("files.dup.copies \(count)", bundle: .atURL(bundleURL))
    }

    static func wasted(_ size: String) -> LocalizedStringResource {
        LocalizedStringResource("files.dup.wasted \(size)", bundle: .atURL(bundleURL))
    }
    static let mapTitle = key("files.map.title")
    static let mapSubtitle = key("files.map.subtitle")
    static let mapOther = key("files.map.other")
    static let mapUnreadable = key("files.map.unreadable")
    static let mapUp = key("files.map.up")
    static let mapHint = key("files.map.hint")

    static func share(percent: Int) -> LocalizedStringResource {
        LocalizedStringResource("files.map.share \(percent)", bundle: .atURL(bundleURL))
    }

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
