import Foundation
import ScanEngine

/// Declarative definition of one cleanup scanner.
///
/// The scanners in CLAUDE.md §6.3 differ only in *where* they look and *what they must not
/// touch*, so they are data rather than code. One reviewable table beats a dozen near-identical
/// classes when the thing being reviewed is which folders an app may delete from.
///
/// Every rule names its roots explicitly. That list becomes the scanner's allowlist in
/// `SafetyKit` (§4.2): nothing outside it can be removed, whatever this scanner reports.
public struct CleanupRule: Sendable, Hashable, Identifiable {
    public let id: ScannerID

    /// Key into this package's String Catalog.
    public let titleKey: String
    public let explanationKey: String

    /// Where the scanner looks. Roots that do not exist on a given Mac are skipped silently.
    public let roots: [CleanupRoot]

    /// Child names never offered, whatever their size.
    ///
    /// For cache roots this is the list of Apple caches that are not safely disposable —
    /// in-flight downloads, iCloud sync state, and similar. Removing one of these does not
    /// break the Mac, but it does lose work or re-download gigabytes, which is not what the
    /// user asked for.
    public let excludedChildNames: Set<String>

    /// Bundle identifiers whose files this scanner touches, so a running owner can be detected
    /// and skipped (§4.5). Matched as a prefix against the child's own name.
    public let ownerBundlePrefixes: [String]

    /// Whether items are preselected. Low-confidence scanners leave the choice to the user.
    public let confidence: ScanItem.Confidence

    /// Off unless the user turns it on (§6.9).
    public let isEnabledByDefault: Bool

    /// Needs Full Disk Access to read its roots (§7).
    public let requiresFullDiskAccess: Bool

    /// Needs the privileged helper, which arrives in Phase 7. Until then the scanner reports
    /// its findings as blocked rather than pretending it can act on them.
    public let requiresHelper: Bool

    public let weight: ScannerWeight

    /// Which children of a listing root are offered.
    public let childFilter: ChildFilter

    public init(
        id: ScannerID,
        titleKey: String,
        explanationKey: String,
        roots: [CleanupRoot],
        excludedChildNames: Set<String> = [],
        ownerBundlePrefixes: [String] = [],
        confidence: ScanItem.Confidence = .high,
        isEnabledByDefault: Bool = true,
        requiresFullDiskAccess: Bool = false,
        requiresHelper: Bool = false,
        weight: ScannerWeight = .light,
        childFilter: ChildFilter = .all
    ) {
        self.id = id
        self.titleKey = titleKey
        self.explanationKey = explanationKey
        self.roots = roots
        self.excludedChildNames = excludedChildNames
        self.ownerBundlePrefixes = ownerBundlePrefixes
        self.confidence = confidence
        self.isEnabledByDefault = isEnabledByDefault
        self.requiresFullDiskAccess = requiresFullDiskAccess
        self.requiresHelper = requiresHelper
        self.weight = weight
        self.childFilter = childFilter
    }

    /// A rule for choosing among a root's children.
    public enum ChildFilter: Sendable, Hashable {
        case all
        /// Only property lists that are readable yet malformed or empty. A file that merely cannot
        /// be read (permission) is *not* malformed and is never offered; Apple's own preferences
        /// fall in that group, so they are excluded by name as well.
        case malformedPropertyLists
        /// The user's Downloads: installers, and anything untouched for `days` days. Partial
        /// downloads and anything changed in the last day are never offered.
        case staleOrInstallers(days: Int)
    }
}

/// A location a scanner looks in.
public struct CleanupRoot: Sendable, Hashable {
    public enum Base: Sendable, Hashable {
        case home
        case absolute
    }

    public let base: Base
    public let path: String

    /// Whether to offer each child separately, or the folder's contents as one item.
    ///
    /// Per-child is right for caches, which are organised by application and where the user
    /// may well want to keep one. Whole-folder is right for things like DerivedData, where the
    /// contents are meaningless individually.
    public let listsChildren: Bool

    /// Bundle identifier prefix of the application that owns this root.
    ///
    /// While a running process matches, everything under the root is skipped (CLAUDE.md §4.5).
    /// Declared explicitly because the identifier is often *not* in the path: Chrome keeps its
    /// cache under `Caches/Google/Chrome`, which names no bundle id at all, so a check that only
    /// looks at path components never saw it was running.
    public var owner: String? { owners.first }

    /// Every application that may be using this root. Usually one; shared folders such as
    /// Adobe's media cache are written by several applications, and any of them running blocks it.
    public let owners: [String]

    /// Name shown for a whole-folder root. Needed because the folder's own name is often
    /// meaningless on its own ("Cache", "Code Cache").
    public let label: String?

    /// A String Catalog key for the name, for roots that need a localized one (a privacy file called
    /// "History" is meaningless without saying whose).
    public let labelKey: String?

    public init(
        base: Base,
        path: String,
        listsChildren: Bool = true,
        owners: [String] = [],
        label: String? = nil,
        labelKey: String? = nil
    ) {
        self.base = base
        self.path = path
        self.listsChildren = listsChildren
        self.owners = owners
        self.label = label
        self.labelKey = labelKey
    }

    public static func home(
        _ path: String,
        listsChildren: Bool = true,
        owner: String? = nil,
        owners: [String] = [],
        label: String? = nil,
        labelKey: String? = nil
    ) -> CleanupRoot {
        CleanupRoot(
            base: .home, path: path, listsChildren: listsChildren,
            owners: owner.map { [$0] } ?? owners, label: label, labelKey: labelKey
        )
    }

    public static func absolute(
        _ path: String,
        listsChildren: Bool = true,
        owner: String? = nil,
        owners: [String] = [],
        label: String? = nil,
        labelKey: String? = nil
    ) -> CleanupRoot {
        CleanupRoot(
            base: .absolute, path: path, listsChildren: listsChildren,
            owners: owner.map { [$0] } ?? owners, label: label, labelKey: labelKey
        )
    }

    /// Resolves against a home directory.
    public func url(home: URL) -> URL {
        switch base {
        case .home: home.appendingPathComponent(path)
        case .absolute: URL(fileURLWithPath: path)
        }
    }
}

/// Which cleanup scanners the user has switched on or off (CLAUDE.md §6.3, §6.9).
///
/// A rule that is off by default (language files) stays off until the user turns it on; one that
/// is on stays on until turned off. Stored in `UserDefaults`, one key per scanner. `UserDefaults`
/// is thread-safe, which is why the wrapper may cross isolation boundaries.
public struct ScannerPreferences: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ rule: CleanupRule) -> String { "cleanup.scanner.\(rule.id.rawValue)" }

    public func isEnabled(_ rule: CleanupRule) -> Bool {
        defaults.object(forKey: key(rule)) as? Bool ?? rule.isEnabledByDefault
    }

    public func setEnabled(_ isOn: Bool, for rule: CleanupRule) {
        defaults.set(isOn, forKey: key(rule))
    }
}

extension CleanupScanner {
    /// The scanners the user has left on.
    public static func enabled(preferences: ScannerPreferences = ScannerPreferences()) -> [CleanupScanner] {
        CleanupCatalogue.all.filter { preferences.isEnabled($0) }.map { CleanupScanner(rule: $0) }
    }
}
