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
        public static let all: [CleanupRule] = [safari, chromium, recentItems]

        public static let safari = CleanupRule(
            id: ScannerID("privacy.safari"),
            titleKey: "privacy.safari.title",
            explanationKey: "privacy.safari.explanation",
            roots: [
                .home("Library/Safari/History.db", listsChildren: false, owner: "com.apple.Safari", labelKey: "privacy.label.history"),
                .home("Library/Safari/LastSession.plist", listsChildren: false, owner: "com.apple.Safari", labelKey: "privacy.label.lastSession"),
                .home("Library/Cookies/Cookies.binarycookies", listsChildren: false, owner: "com.apple.Safari", labelKey: "privacy.label.cookies")
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
            } },
            ownerBundlePrefixes: profiles.map(\.owner),
            confidence: .low
        )

        public static let recentItems = CleanupRule(
            id: ScannerID("privacy.recentItems"),
            titleKey: "privacy.recentItems.title",
            explanationKey: "privacy.recentItems.explanation",
            roots: [.home("Library/Application Support/com.apple.sharedfilelist", listsChildren: true)],
            confidence: .low
        )

        private static let profiles: [(path: String, owner: String)] = [
            ("Google/Chrome", "com.google.Chrome"),
            ("BraveSoftware/Brave-Browser", "com.brave.Browser"),
            ("Microsoft Edge", "com.microsoft.edgemac"),
            ("Arc/User Data", "company.thebrowser.Browser")
        ]

        private static let files: [(path: String, name: String)] = [
            ("History", "history"), ("Cookies", "cookies"), ("Network/Cookies", "cookies"),
            ("Web Data", "formData"), ("Top Sites", "history")
        ]
    }
}

extension CleanupModel {
    /// A model over the browsing-trace scanners, for the Privacy screen.
    public static func privacy(history: HistoryStore?) -> CleanupModel {
        CleanupModel(scanners: CleanupCatalogue.Privacy.all.map { CleanupScanner(rule: $0) }, history: history)
    }
}
