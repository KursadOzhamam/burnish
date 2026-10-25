import Testing
import Foundation
import CoreKit
import ScanEngine
import SafetyKit
import SafetyKitMac
@testable import Cleanup

/// Browser-profile folders: only the named files are found, and only those can ever be removed.
@Suite("Profile files", .serialized)
struct ProfileFilesTests {

    private func withHome(_ body: (URL) async throws -> Void) async throws {
        let home = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("BurnishProfileHome-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer {
            // Fixture teardown, not product code.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: home)
        }
        try await body(home)
    }

    private func write(_ relative: String, in home: URL) throws {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 4_096).write(to: url)
    }

    private func scanner(_ rule: CleanupRule, home: URL, running: Set<String> = []) -> CleanupScanner {
        CleanupScanner(rule: rule, home: home, inspector: StaticRunningApplicationInspector(running))
    }

    private let firefox = "Library/Application Support/Firefox/Profiles"
    private let chrome = "Library/Application Support/Google/Chrome"

    @Test("Firefox: cookies and form history are found in every profile; bookmarks and passwords are not")
    func firefoxNamedFilesOnly() async throws {
        try await withHome { home in
            for profile in ["a1b2.default-release", "c3d4.work"] {
                try write("\(firefox)/\(profile)/cookies.sqlite", in: home)
                try write("\(firefox)/\(profile)/formhistory.sqlite", in: home)
                try write("\(firefox)/\(profile)/places.sqlite", in: home)
                try write("\(firefox)/\(profile)/logins.json", in: home)
            }
            let items = try await scanner(CleanupCatalogue.Privacy.firefox, home: home).scan { _ in }
            let names = Set(items.map(\.url.lastPathComponent))
            #expect(names == ["cookies.sqlite", "formhistory.sqlite"])
            #expect(items.count == 4)
            #expect(items.contains { $0.displayName == "cookies.sqlite · a1b2.default-release" })
            #expect(items.allSatisfy { $0.confidence == .low })
        }
    }

    @Test("Extra Chromium profiles are found; Default is left to the Default scanner, so nothing is counted twice")
    func chromiumExtraProfiles() async throws {
        try await withHome { home in
            try write("\(chrome)/Default/History", in: home)
            try write("\(chrome)/Profile 1/History", in: home)
            try write("\(chrome)/Profile 1/Network/Cookies", in: home)
            try write("\(chrome)/Guest Profile/History", in: home)
            try write("\(chrome)/System Profile/History", in: home)

            let extra = try await scanner(CleanupCatalogue.Privacy.chromiumProfiles, home: home).scan { _ in }
            let paths = Set(extra.map { $0.url.path.replacingOccurrences(of: home.path + "/" + chrome + "/", with: "") })
            #expect(paths == ["Profile 1/History", "Profile 1/Network/Cookies", "Guest Profile/History"])

            let defaults = try await scanner(CleanupCatalogue.Privacy.chromium, home: home).scan { _ in }
            #expect(Set(defaults.map(\.url)).isDisjoint(with: Set(extra.map(\.url))))
        }
    }

    @Test("Saved passwords beside an offered file are outside the allowlist")
    func passwordsAreUnreachable() async throws {
        try await withHome { home in
            try write("\(chrome)/Profile 1/History", in: home)
            try write("\(chrome)/Profile 1/Login Data", in: home)
            let scanner = scanner(CleanupCatalogue.Privacy.chromiumProfiles, home: home)
            let guardrail = PathGuard(allowedRoots: scanner.allowedRoots, allowedTargets: scanner.allowedTargets, home: home)

            #expect(scanner.allowedRoots.isEmpty)
            #expect(guardrail.isAllowed(home.appendingPathComponent("\(chrome)/Profile 1/History")))
            #expect(!guardrail.isAllowed(home.appendingPathComponent("\(chrome)/Profile 1/Login Data")))
            #expect(!guardrail.isAllowed(home.appendingPathComponent("\(chrome)/Profile 1")))
            #expect(!guardrail.isAllowed(home.appendingPathComponent(chrome)))
        }
    }

    @Test("A symlinked profile folder is not followed")
    func symlinkedProfileIgnored() async throws {
        try await withHome { home in
            try write("Elsewhere/History", in: home)
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(chrome), withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(
                at: home.appendingPathComponent("\(chrome)/Profile 9"),
                withDestinationURL: home.appendingPathComponent("Elsewhere")
            )
            let scanner = scanner(CleanupCatalogue.Privacy.chromiumProfiles, home: home)
            #expect(try await scanner.scan { _ in }.isEmpty)
            #expect(scanner.allowedTargets.isEmpty)
        }
    }

    @Test("A profile file is blocked while its browser runs")
    func blockedWhileRunning() async throws {
        try await withHome { home in
            try write("\(firefox)/x.default/cookies.sqlite", in: home)
            let items = try await scanner(CleanupCatalogue.Privacy.firefox, home: home, running: ["org.mozilla.firefox"])
                .scan { _ in }
            #expect(items.count == 1)
            #expect(items.allSatisfy { $0.blockedReason == .ownerRunning })
        }
    }

    @Test("Every new browser root declares its owner")
    func ownersDeclared() {
        for rule in [CleanupCatalogue.Privacy.chromiumProfiles, CleanupCatalogue.Privacy.firefox] {
            for root in rule.roots { #expect(!root.owners.isEmpty, "\(root.path)") }
        }
    }
}

/// Developer caches outside `~/Library`.
@Suite("Home-folder caches", .serialized)
struct HomeCacheTests {

    @Test("Package-manager caches are the cache folders only, never the tool's own folder")
    func cacheFoldersOnly() {
        let paths = Set(CleanupCatalogue.packageManagerCaches.roots.map(\.path))
        // These hold settings, credentials or the modules a build uses, not just downloads.
        let toolFolders: Set<String> = [".npm", ".gradle", ".cocoapods", ".yarn", "go", "go/pkg/mod", "Library/pnpm"]
        #expect(paths.isDisjoint(with: toolFolders))
        #expect(CleanupCatalogue.packageManagerCaches.roots.allSatisfy { !$0.listsChildren && $0.label != nil })
    }

    @Test("Package caches are medium confidence; tool caches, which may hold large models, are never preselected")
    func confidenceLevels() {
        #expect(CleanupCatalogue.packageManagerCaches.confidence == .medium)
        #expect(CleanupCatalogue.toolCaches.confidence == .low)
    }

    @Test("The npm cache is found whole and the guard allows exactly it")
    func npmFoundWhole() async throws {
        let home = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishNpm-\(UUID().uuidString)")
        defer {
            // Fixture teardown, not product code.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: home)
        }
        let cache = home.appendingPathComponent(".npm/_cacache/index-v5")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8_192).write(to: cache.appendingPathComponent("entry"))
        try Data(repeating: 1, count: 100).write(to: home.appendingPathComponent(".npm/settings"))

        let scanner = CleanupScanner(
            rule: CleanupCatalogue.packageManagerCaches, home: home, inspector: StaticRunningApplicationInspector([])
        )
        let items = try await scanner.scan { _ in }
        #expect(items.map(\.displayName) == ["npm"])
        let guardrail = PathGuard(allowedRoots: scanner.allowedRoots, allowedTargets: scanner.allowedTargets, home: home)
        #expect(guardrail.isAllowed(home.appendingPathComponent(".npm/_cacache")))
        #expect(!guardrail.isAllowed(home.appendingPathComponent(".npm/settings")))
    }
}
