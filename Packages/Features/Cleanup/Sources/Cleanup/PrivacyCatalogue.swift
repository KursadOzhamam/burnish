import Foundation
import ScanEngine
import SafetyKit
import SafetyKitMac

extension CleanupCatalogue {
    /// Browsing traces (CLAUDE.md §6.4, privacy). Each browser is its own scanner so the user can
    /// pick one. Everything is low confidence and never preselected: history and cookies are the
    /// user's own data, and removing cookies signs the user out of sites. Removal goes to the
    /// Trash like everything else (CLAUDE.md §4.1: permanent deletion is for the shredder and
    /// emptying the Trash only), so a trace is truly gone once the Trash is emptied.
    /// A browser that is open is skipped (§4.5).
    public enum Privacy {
        public static let all: [CleanupRule] = [safari, chromium, chromiumProfiles, firefox, recentItems, downloadLog]

        public static let safari = CleanupRule(
            id: ScannerID("privacy.safari"),
            titleKey: "privacy.safari.title",
            explanationKey: "privacy.safari.explanation",
            roots: [
                .home("Library/Safari/History.db", listsChildren: false, owner: "com.apple.Safari", labelKey: "privacy.label.history"),
                // SQLite's write-ahead log holds recent visits not yet folded into History.db.
                .home("Library/Safari/History.db-wal", listsChildren: false, owner: "com.apple.Safari", labelKey: "privacy.label.history"),
                .home("Library/Safari/LastSession.plist", listsChildren: false, owner: "com.apple.Safari", labelKey: "privacy.label.lastSession"),
                .home("Library/Cookies/Cookies.binarycookies", listsChildren: false, owner: "com.apple.Safari", labelKey: "privacy.label.cookies"),
                // Current Safari keeps its cookies inside its container rather than ~/Library/Cookies.
                .home(
                    "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies",
                    listsChildren: false, owner: "com.apple.Safari", labelKey: "privacy.label.cookies"
                )
            ],
            ownerBundlePrefixes: ["com.apple.Safari"],
            confidence: .low,
            requiresFullDiskAccess: true
        )

        /// Chrome, Brave, Edge and Arc share one profile layout.
        public static let chromium = CleanupRule(
            id: ScannerID("privacy.chromium"),
            titleKey: "privacy.chromium.title",
            explanationKey: "privacy.chromium.explanation",
            roots: profiles.flatMap { profile in files.map { file in
                CleanupRoot.home(
                    "Library/Application Support/\(profile.path)/Default/\(file.path)",
                    listsChildren: false, owner: profile.owner, label: nil, labelKey: nil
                )
            } } + operaProfiles.flatMap { profile in files.map { file in
                // Opera keeps its main profile in the top folder itself, with no "Default".
                CleanupRoot.home(
                    "Library/Application Support/\(profile.path)/\(file.path)",
                    listsChildren: false, owner: profile.owner, label: nil, labelKey: nil
                )
            } },
            ownerBundlePrefixes: profiles.map(\.owner) + operaProfiles.map(\.owner),
            confidence: .low
        )

        /// The same files as `chromium`, in every profile other than Default: the extra profiles
        /// ("Profile 1", "Profile 2"…) and the guest profile. Default stays with `chromium`, so no
        /// file is reported by both scanners (§10.4).
        public static let chromiumProfiles = CleanupRule(
            id: ScannerID("privacy.chromiumProfiles"),
            titleKey: "privacy.chromiumProfiles.title",
            explanationKey: "privacy.chromiumProfiles.explanation",
            roots: profiles.map { profile in
                CleanupRoot.profiles(
                    "Library/Application Support/\(profile.path)",
                    files: files.map(\.path),
                    prefixes: ["Profile ", "Guest Profile"],
                    owner: profile.owner
                )
            } + operaProfiles.map { profile in
                // Opera's extra profiles live under "_side_profiles", one folder each.
                CleanupRoot.profiles(
                    "Library/Application Support/\(profile.path)/_side_profiles",
                    files: files.map(\.path),
                    owner: profile.owner
                )
            },
            ownerBundlePrefixes: profiles.map(\.owner) + operaProfiles.map(\.owner),
            confidence: .low
        )

        /// Firefox's cookies, form history and saved session, in every profile.
        ///
        /// `places.sqlite` is deliberately absent: Firefox keeps bookmarks in the same database as
        /// history, so removing it to clear history would silently take the bookmarks too.
        public static let firefox = CleanupRule(
            id: ScannerID("privacy.firefox"),
            titleKey: "privacy.firefox.title",
            explanationKey: "privacy.firefox.explanation",
            roots: [
                .profiles(
                    "Library/Application Support/Firefox/Profiles",
                    files: ["cookies.sqlite", "cookies.sqlite-wal", "formhistory.sqlite", "sessionstore.jsonlz4"],
                    owner: "org.mozilla.firefox"
                )
            ],
            ownerBundlePrefixes: ["org.mozilla.firefox"],
            confidence: .low
        )

        public static let recentItems = CleanupRule(
            id: ScannerID("privacy.recentItems"),
            titleKey: "privacy.recentItems.title",
            explanationKey: "privacy.recentItems.explanation",
            roots: [.home("Library/Application Support/com.apple.sharedfilelist", listsChildren: true)],
            confidence: .low
        )

        /// macOS's log of every file downloaded from the internet: source address, date and the
        /// application that fetched it. Kept for Gatekeeper's warnings; recreated when needed.
        public static let downloadLog = CleanupRule(
            id: ScannerID("privacy.downloadLog"),
            titleKey: "privacy.downloadLog.title",
            explanationKey: "privacy.downloadLog.explanation",
            roots: [
                .home(
                    "Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2",
                    listsChildren: false, labelKey: "privacy.label.downloadLog"
                )
            ],
            confidence: .low
        )

        private static let profiles: [(path: String, owner: String)] = [
            ("Google/Chrome", "com.google.Chrome"),
            ("BraveSoftware/Brave-Browser", "com.brave.Browser"),
            ("Microsoft Edge", "com.microsoft.edgemac"),
            ("Arc/User Data", "company.thebrowser.Browser"),
            ("Vivaldi", "com.vivaldi.Vivaldi")
        ]

        /// Opera and Opera GX: Chromium files, but their own folder layout.
        private static let operaProfiles: [(path: String, owner: String)] = [
            ("com.operasoftware.Opera", "com.operasoftware.Opera"),
            ("com.operasoftware.OperaGX", "com.operasoftware.OperaGX")
        ]

        /// Saved passwords ("Login Data") are never on this list.
        private static let files: [(path: String, name: String)] = [
            ("History", "history"), ("History-journal", "history"), ("Visited Links", "history"),
            ("Top Sites", "history"), ("Top Sites-journal", "history"),
            ("Shortcuts", "history"), ("Shortcuts-journal", "history"),
            ("Cookies", "cookies"), ("Cookies-journal", "cookies"),
            ("Network/Cookies", "cookies"), ("Network/Cookies-journal", "cookies"),
            ("Web Data", "formData")
        ]
    }
}

extension CleanupModel {
    /// A model over the browsing-trace scanners, for the Privacy screen.
    public static func privacy(history: HistoryStore?) -> CleanupModel {
        CleanupModel(scanners: CleanupCatalogue.Privacy.all.map { CleanupScanner(rule: $0) }, history: history)
    }
}
