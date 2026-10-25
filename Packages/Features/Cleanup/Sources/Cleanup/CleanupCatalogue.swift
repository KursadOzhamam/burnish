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
        packageManagerCaches,
        toolCaches,
        xcodeDeviceSupport,
        xcodeArchives,
        browserCaches,
        appCaches,
        adobeMediaCaches,
        brokenPreferences,
        downloads,
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

    /// Download caches that package managers keep in dot-folders of the home directory, outside
    /// `~/Library` and so outside `developerJunk`.
    ///
    /// Each entry is the cache folder alone, never the tool's whole folder: `~/.gradle` also holds
    /// settings and credentials, and `~/go/pkg/mod` holds the modules a build actually uses (only
    /// its `cache` subfolder is the download cache). Nothing is lost, only re-downloaded on the
    /// next install or build, so the items are preselected — but at medium confidence, because
    /// that download can be large.
    public static let packageManagerCaches = CleanupRule(
        id: ScannerID("cleanup.packageManagerCaches"),
        titleKey: "cleanup.packageManagerCaches.title",
        explanationKey: "cleanup.packageManagerCaches.explanation",
        roots: [
            .home(".npm/_cacache", listsChildren: false, label: "npm"),
            .home(".gradle/caches", listsChildren: false, label: "Gradle"),
            .home(".cocoapods/repos", listsChildren: false, label: "CocoaPods"),
            .home("Library/pnpm/store", listsChildren: false, label: "pnpm"),
            .home(".pnpm-store", listsChildren: false, label: "pnpm"),
            .home(".yarn/berry/cache", listsChildren: false, label: "Yarn"),
            .home("go/pkg/mod/cache", listsChildren: false, label: "Go")
        ],
        confidence: .medium
    )

    /// `~/.cache`: the shared cache folder of command-line tools (pip, uv, Hugging Face,
    /// Puppeteer and others).
    ///
    /// Listed per tool and never preselected. Some entries are downloaded machine-learning models
    /// of many gigabytes; they come back on next use, but that download can take a long time.
    public static let toolCaches = CleanupRule(
        id: ScannerID("cleanup.toolCaches"),
        titleKey: "cleanup.toolCaches.title",
        explanationKey: "cleanup.toolCaches.explanation",
        roots: [.home(".cache")],
        confidence: .low
    )

    /// Debug symbols Xcode keeps for every device and OS version it has connected to.
    ///
    /// Often the largest single item on a developer's Mac (12 GB here). Xcode rebuilds a folder
    /// the next time that device is plugged in, but that first sync takes minutes, so nothing
    /// is preselected: the user decides which versions they will not need again.
    public static let xcodeDeviceSupport = CleanupRule(
        id: ScannerID("cleanup.xcodeDeviceSupport"),
        titleKey: "cleanup.xcodeDeviceSupport.title",
        explanationKey: "cleanup.xcodeDeviceSupport.explanation",
        roots: [
            .home("Library/Developer/Xcode/iOS DeviceSupport", owner: "com.apple.dt.Xcode"),
            .home("Library/Developer/Xcode/watchOS DeviceSupport", owner: "com.apple.dt.Xcode"),
            .home("Library/Developer/Xcode/tvOS DeviceSupport", owner: "com.apple.dt.Xcode"),
            .home("Library/Developer/Xcode/visionOS DeviceSupport", owner: "com.apple.dt.Xcode")
        ],
        confidence: .low
    )

    /// Archives of builds the user has shipped.
    ///
    /// The symbols needed to read a crash report from a released version may exist only here, so
    /// losing one silently would be a real loss. Listed, never preselected.
    public static let xcodeArchives = CleanupRule(
        id: ScannerID("cleanup.xcodeArchives"),
        titleKey: "cleanup.xcodeArchives.title",
        explanationKey: "cleanup.xcodeArchives.explanation",
        roots: [.home("Library/Developer/Xcode/Archives", owner: "com.apple.dt.Xcode")],
        confidence: .low
    )

    /// Browser caches. Each browser is skipped while it is running (§4.5, §6.3).
    public static let browserCaches = CleanupRule(
        id: ScannerID("cleanup.browserCaches"),
        titleKey: "cleanup.browserCaches.title",
        explanationKey: "cleanup.browserCaches.explanation",
        roots: [
            .home("Library/Caches/com.apple.Safari", owner: "com.apple.Safari"),
            .home("Library/Caches/Google/Chrome", owner: "com.google.Chrome"),
            .home("Library/Caches/Firefox", owner: "org.mozilla.firefox"),
            .home("Library/Caches/com.microsoft.edgemac", owner: "com.microsoft.edgemac"),
            .home("Library/Caches/BraveSoftware", owner: "com.brave.Browser"),
            .home("Library/Caches/company.thebrowser.Browser", owner: "company.thebrowser.Browser")
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

    /// Caches that Electron and Chromium based applications keep under Application Support.
    ///
    /// Each entry is one verified cache folder, not the application's folder: the rest of what
    /// lives beside it (profiles, databases, settings) is user data and is never listed. Each is
    /// offered whole, because the files inside are meaningless one by one, and skipped while its
    /// application runs (§4.5).
    public static let appCaches = CleanupRule(
        id: ScannerID("cleanup.appCaches"),
        titleKey: "cleanup.appCaches.title",
        explanationKey: "cleanup.appCaches.explanation",
        roots: [
            .home("Library/Application Support/Notion/Partitions/notion/Cache",
                  listsChildren: false, owner: "notion.id", label: "Notion"),
            .home("Library/Application Support/Claude/Cache",
                  listsChildren: false, owner: "com.anthropic.claudefordesktop", label: "Claude"),
            .home("Library/Application Support/Claude/Code Cache",
                  listsChildren: false, owner: "com.anthropic.claudefordesktop", label: "Claude (code)"),
            .home("Library/Application Support/Figma/DesktopProfile/v43/Cache",
                  listsChildren: false, owner: "com.figma.Desktop", label: "Figma"),
            .home("Library/Application Support/Figma/DesktopProfile/v43/Code Cache",
                  listsChildren: false, owner: "com.figma.Desktop", label: "Figma (code)"),
            .home("Library/Application Support/Cursor/CachedData",
                  listsChildren: false, owner: "com.todesktop.230313mzl4w4u92", label: "Cursor"),
            .home("Library/Application Support/Code/CachedData",
                  listsChildren: false, owner: "com.microsoft.VSCode", label: "Visual Studio Code"),
            .home("Library/Application Support/Code/CachedExtensionVSIXs",
                  listsChildren: false, owner: "com.microsoft.VSCode", label: "Visual Studio Code (extensions)")
        ],
        confidence: .medium
    )

    /// Adobe's shared media and peak-file caches.
    ///
    /// Several Adobe applications write to the same folder, so any of them running blocks it.
    /// Nothing is preselected: rebuilding a large project's cache can take a long time even
    /// though no work is lost.
    public static let adobeMediaCaches = CleanupRule(
        id: ScannerID("cleanup.adobeMediaCaches"),
        titleKey: "cleanup.adobeMediaCaches.title",
        explanationKey: "cleanup.adobeMediaCaches.explanation",
        roots: [
            .home("Library/Application Support/Adobe/Common/Media Cache Files",
                  listsChildren: false, owners: Self.adobeOwners, label: "Adobe Media Cache"),
            .home("Library/Application Support/Adobe/Common/Peak Files",
                  listsChildren: false, owners: Self.adobeOwners, label: "Adobe Peak Files")
        ],
        confidence: .low
    )

    private static let adobeOwners = [
        "com.adobe.PremierePro",
        "com.adobe.Audition",
        "com.adobe.AfterEffects",
        "com.adobe.ame",
        "com.adobe.Character-Animator",
        "com.adobe.Photoshop"
    ]

    /// Preference files that are empty or cannot be parsed.
    ///
    /// Nothing is preselected: a preference file is the user's settings, even when it is broken,
    /// and the application that owns it recreates it. Apple's own files are never offered.
    public static let brokenPreferences = CleanupRule(
        id: ScannerID("cleanup.brokenPreferences"),
        titleKey: "cleanup.brokenPreferences.title",
        explanationKey: "cleanup.brokenPreferences.explanation",
        roots: [.home("Library/Preferences")],
        confidence: .low,
        childFilter: .malformedPropertyLists
    )

    /// The user's Downloads folder (CLAUDE.md §6.7).
    ///
    /// This is the user's own content, so: nothing is preselected, the folder itself is never a
    /// target (only its direct contents), and only the Trash is offered, never permanent removal.
    public static let downloads = CleanupRule(
        id: ScannerID("cleanup.downloads"),
        titleKey: "cleanup.downloads.title",
        explanationKey: "cleanup.downloads.explanation",
        roots: [.home("Downloads")],
        confidence: .low,
        childFilter: .staleOrInstallers(days: 30)
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
