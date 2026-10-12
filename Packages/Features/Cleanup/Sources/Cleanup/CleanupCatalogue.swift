import Foundation
import ScanEngine

/// Every cleanup scanner Burnish offers — CLAUDE.md §6.3.
///
/// Read this as the answer to "what can this app delete?". Each rule names its roots, and those
/// roots become the scanner's allowlist in `SafetyKit`, so nothing outside them is reachable
/// even if a scanner misbehaves (§4.2).
public enum CleanupCatalogue {

    /// Apple caches under `~/Library/Caches` that are not safely disposable.
    ///
    /// None of these would break macOS, but each one loses work or costs the user a large
    /// re-download — in-flight App Store purchases, iCloud sync state, background downloads.
    /// "Technically removable" is not the bar; "the user will not regret it" is.
    /// Cache folders owned by the browser scanner rather than the general cache scanner.
    ///
    /// These sit inside `~/Library/Caches`, so without this both scanners would report the same
    /// bytes and the total would be inflated — exactly what §10.4 forbids. Worse, the general
    /// scanner declares no browser ownership, so it would happily offer Safari's cache while
    /// Safari was running, stepping straight past §4.5. One owner per path.
    static let browserOwnedCacheFolders: Set<String> = [
        "com.apple.Safari",
        "Google",
        "Firefox",
        "Mozilla",
        "com.microsoft.edgemac",
        "BraveSoftware",
        "company.thebrowser.Browser"
    ]

    /// Cache folders owned by the developer-junk scanner rather than the general one.
    ///
    /// Same reasoning as `browserOwnedCacheFolders`: these live under `~/Library/Caches`, and
    /// two scanners reporting the same bytes inflates the total.
    static let developerOwnedCacheFolders: Set<String> = [
        "org.swift.swiftpm",
        "CocoaPods",
        "org.carthage.CarthageKit",
        "Homebrew",
        "com.apple.dt.Xcode"
    ]

    static let protectedUserCaches: Set<String> = [
        "com.apple.appstore",
        "com.apple.commerce",
        "com.apple.nsurlsessiond",      // background downloads in progress
        "com.apple.bird",               // iCloud Drive sync state
        "CloudKit",
        "com.apple.cloudd",
        "com.apple.containermanagerd",
        "com.apple.iCloudHelper",
        "com.apple.Safari.SafeBrowsing",
        "com.apple.AMPLibraryAgent",    // Music library state
        "com.apple.photolibraryd",
        "FamilyCircle",
        "com.apple.ap.adprivacyd"
    ]

    public static let all: [CleanupRule] = [
        userCaches,
        userLogs,
        developerJunk,
        browserCaches,
        mailDownloads,
        mobileBackups,
        userTrash,
        systemCaches
    ]

    /// `~/Library/Caches` — the largest safe win on most Macs.
    public static let userCaches = CleanupRule(
        id: ScannerID("cleanup.userCaches"),
        titleKey: "cleanup.userCaches.title",
        explanationKey: "cleanup.userCaches.explanation",
        roots: [.home("Library/Caches")],
        // Browser folders belong to the browser scanner; see browserOwnedCacheFolders.
        excludedChildNames: protectedUserCaches
            .union(browserOwnedCacheFolders)
            .union(developerOwnedCacheFolders),
        confidence: .high
    )

    /// `~/Library/Logs` — diagnostic output, rebuilt as needed.
    public static let userLogs = CleanupRule(
        id: ScannerID("cleanup.userLogs"),
        titleKey: "cleanup.userLogs.title",
        explanationKey: "cleanup.userLogs.explanation",
        roots: [.home("Library/Logs")],
        confidence: .high
    )

    /// Xcode and package-manager leftovers. Often the single biggest item on a developer's Mac.
    ///
    /// `DerivedData` and `Archives` are listed whole because their contents mean nothing
    /// individually. Archives are *not* preselected: they are the only copy of a shipped build's
    /// symbols, and losing them silently would be a real loss.
    public static let developerJunk = CleanupRule(
        id: ScannerID("cleanup.developerJunk"),
        titleKey: "cleanup.developerJunk.title",
        explanationKey: "cleanup.developerJunk.explanation",
        roots: [
            .home("Library/Developer/Xcode/DerivedData"),
            .home("Library/Developer/CoreSimulator/Caches"),
            .home("Library/Caches/org.swift.swiftpm"),
            .home("Library/Caches/CocoaPods"),
            .home("Library/Caches/org.carthage.CarthageKit"),
            .home("Library/Caches/Homebrew"),
            .home("Library/Caches/com.apple.dt.Xcode")
        ],
        confidence: .high
    )

    /// Browser caches. Each browser is skipped while it is running (§4.5, §6.3).
    public static let browserCaches = CleanupRule(
        id: ScannerID("cleanup.browserCaches"),
        titleKey: "cleanup.browserCaches.title",
        explanationKey: "cleanup.browserCaches.explanation",
        roots: [
            .home("Library/Caches/com.apple.Safari"),
            .home("Library/Caches/Google/Chrome"),
            .home("Library/Caches/Firefox"),
            .home("Library/Caches/com.microsoft.edgemac"),
            .home("Library/Caches/BraveSoftware"),
            .home("Library/Caches/company.thebrowser.Browser")
        ],
        ownerBundlePrefixes: [
            "com.apple.Safari",
            "com.google.Chrome",
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "company.thebrowser.Browser"
        ],
        confidence: .high,
        requiresFullDiskAccess: true
    )

    /// Mail's downloaded attachments. The mailbox database itself is on the protected list
    /// (§4.3) and is never touched.
    public static let mailDownloads = CleanupRule(
        id: ScannerID("cleanup.mailDownloads"),
        titleKey: "cleanup.mailDownloads.title",
        explanationKey: "cleanup.mailDownloads.explanation",
        roots: [.home("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")],
        ownerBundlePrefixes: ["com.apple.mail"],
        confidence: .medium,
        requiresFullDiskAccess: true
    )

    /// iOS and iPadOS backups, and downloaded firmware images.
    ///
    /// Never preselected. A device backup may be someone's only copy of a phone, and the whole
    /// point of §4 is that we do not make that call for them.
    public static let mobileBackups = CleanupRule(
        id: ScannerID("cleanup.mobileBackups"),
        titleKey: "cleanup.mobileBackups.title",
        explanationKey: "cleanup.mobileBackups.explanation",
        roots: [
            .home("Library/Application Support/MobileSync/Backup"),
            .home("Library/iTunes/iPhone Software Updates"),
            .home("Library/iTunes/iPad Software Updates")
        ],
        confidence: .low,
        requiresFullDiskAccess: true
    )

    /// The user's Trash.
    ///
    /// Emptying the Trash is permanent by definition, so this scanner's items are removed with
    /// `DeletionMode.permanent` and carry the extra confirmation §4.1 requires.
    public static let userTrash = CleanupRule(
        id: ScannerID("cleanup.userTrash"),
        titleKey: "cleanup.userTrash.title",
        explanationKey: "cleanup.userTrash.explanation",
        roots: [.home(".Trash")],
        confidence: .medium
    )

    /// System caches and logs.
    ///
    /// Listed so the user can see what is there, but not actionable until the privileged helper
    /// exists (Phase 7). Showing the finding and saying plainly that it cannot be acted on yet
    /// beats hiding it or pretending otherwise.
    public static let systemCaches = CleanupRule(
        id: ScannerID("cleanup.systemCaches"),
        titleKey: "cleanup.systemCaches.title",
        explanationKey: "cleanup.systemCaches.explanation",
        roots: [
            .absolute("/Library/Caches"),
            .absolute("/Library/Logs")
        ],
        confidence: .medium,
        requiresFullDiskAccess: true,
        requiresHelper: true
    )

    /// Scanners whose deletions are permanent rather than a move to the Trash.
    public static let permanentScanners: Set<ScannerID> = [userTrash.id]
}
