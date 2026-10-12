import Testing
import Foundation
import CoreKit
import ScanEngine
import SafetyKitMac
@testable import Cleanup

/// CLAUDE.md §9: every scanner is tested against a synthetic tree, never a real system folder.
@Suite("CleanupScanner", .serialized)
struct CleanupScannerTests {

    /// Builds a fake home directory and removes it afterwards.
    private func withHome(_ body: (URL) async throws -> Void) async throws {
        let home = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("BurnishHome-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        // Fixture teardown, not product code.
        // swiftlint:disable:next no_direct_remove_item
        defer { try? FileManager.default.removeItem(at: home) }
        try await body(home)
    }

    @discardableResult
    private func write(_ bytes: Int, to url: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(repeating: 0x43, count: bytes).write(to: url)
        return url
    }

    private func scan(
        _ rule: CleanupRule,
        home: URL,
        running: Set<String> = []
    ) async throws -> [ScanItem] {
        let scanner = CleanupScanner(
            rule: rule,
            home: home,
            inspector: StaticRunningApplicationInspector(running)
        )
        return try await scanner.scan { _ in }
    }

    @Test("Each cache folder is offered as its own item")
    func cachesAreListedPerApplication() async throws {
        try await withHome { home in
            try write(4_096, to: home.appendingPathComponent("Library/Caches/com.example.a/x"))
            try write(4_096, to: home.appendingPathComponent("Library/Caches/com.example.b/y"))

            let items = try await scan(CleanupCatalogue.userCaches, home: home)
            #expect(items.count == 2)
            #expect(items.allSatisfy { $0.size.bytes > 0 })
        }
    }

    @Test("Protected Apple caches are not offered at all",
          arguments: Array(CleanupCatalogue.protectedUserCaches))
    func protectedCachesAreNeverOffered(name: String) async throws {
        try await withHome { home in
            try write(8_192, to: home.appendingPathComponent("Library/Caches/\(name)/data"))
            try write(8_192, to: home.appendingPathComponent("Library/Caches/com.ok.app/data"))

            let items = try await scan(CleanupCatalogue.userCaches, home: home)

            // Excluded entirely, not merely unselected: "select all" must not reach it.
            #expect(items.count == 1)
            #expect(items.first?.displayName == "com.ok.app")
        }
    }

    @Test("Empty folders are not offered as findings")
    func emptyFoldersAreSkipped() async throws {
        try await withHome { home in
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent("Library/Caches/com.empty.app"),
                withIntermediateDirectories: true
            )
            let items = try await scan(CleanupCatalogue.userCaches, home: home)
            #expect(items.isEmpty, "a zero-byte finding is noise, not a finding")
        }
    }

    @Test("A missing root is skipped rather than reported as an error")
    func missingRootIsSkipped() async throws {
        try await withHome { home in
            let items = try await scan(CleanupCatalogue.developerJunk, home: home)
            #expect(items.isEmpty)
        }
    }

    @Test("A browser's cache is blocked while the browser is running — §4.5")
    func runningBrowserBlocksItsCache() async throws {
        try await withHome { home in
            try write(4_096, to: home.appendingPathComponent(
                "Library/Caches/com.apple.Safari/WebKitCache/blob"
            ))

            let items = try await scan(
                CleanupCatalogue.browserCaches,
                home: home,
                running: ["com.apple.Safari"]
            )

            #expect(!items.isEmpty)
            #expect(items.allSatisfy { $0.blockedReason == .ownerRunning })
            #expect(items.allSatisfy { !$0.isSelectedByDefault })
        }
    }

    @Test("The same cache is actionable when the browser is closed")
    func closedBrowserLeavesCacheActionable() async throws {
        try await withHome { home in
            try write(4_096, to: home.appendingPathComponent(
                "Library/Caches/com.apple.Safari/WebKitCache/blob"
            ))
            let items = try await scan(CleanupCatalogue.browserCaches, home: home)
            #expect(items.allSatisfy { $0.isActionable })
        }
    }

    @Test("System caches report as needing the helper, not as ready to delete")
    func systemCachesNeedTheHelper() async throws {
        // Uses the real /Library/Caches, which exists on every Mac and is only read here.
        let scanner = CleanupScanner(
            rule: CleanupCatalogue.systemCaches,
            inspector: StaticRunningApplicationInspector()
        )
        let items = try await scanner.scan { _ in }

        // Phase 7 adds the helper; until then these must not look actionable.
        #expect(items.allSatisfy { $0.blockedReason == .needsHelper })
        #expect(items.allSatisfy { !$0.isSelectedByDefault })
    }

    @Test("Backups and firmware are found but never preselected — the user decides")
    func backupsAreNotPreselected() async throws {
        try await withHome { home in
            try write(16_384, to: home.appendingPathComponent(
                "Library/Application Support/MobileSync/Backup/device-1/Manifest.db"
            ))

            let items = try await scan(CleanupCatalogue.mobileBackups, home: home)

            #expect(items.count == 1)
            #expect(items.first?.confidence == .low)
            #expect(items.allSatisfy { !$0.isSelectedByDefault })
        }
    }

    @Test("Scanning is cancellable — §8")
    func scanningIsCancellable() async throws {
        try await withHome { home in
            for index in 0..<30 {
                try write(1_024, to: home.appendingPathComponent(
                    "Library/Caches/com.example.\(index)/data"
                ))
            }

            let scanner = CleanupScanner(
                rule: CleanupCatalogue.userCaches,
                home: home,
                inspector: StaticRunningApplicationInspector()
            )

            let task = Task { try await scanner.scan { _ in } }
            task.cancel()

            await #expect(throws: (any Error).self) { try await task.value }
        }
    }

    @Test("Progress reports a rising total and the path being examined — §5.5")
    func progressIsReported() async throws {
        try await withHome { home in
            for index in 0..<4 {
                try write(2_048, to: home.appendingPathComponent(
                    "Library/Caches/com.example.\(index)/data"
                ))
            }

            final class Box: @unchecked Sendable { var reports: [ScanProgress] = [] }
            let box = Box()

            let scanner = CleanupScanner(
                rule: CleanupCatalogue.userCaches,
                home: home,
                inspector: StaticRunningApplicationInspector()
            )
            _ = try await scanner.scan { box.reports.append($0) }

            #expect(box.reports.count == 4)
            #expect(box.reports.map(\.discovered.bytes) == box.reports.map(\.discovered.bytes).sorted())
            #expect(box.reports.allSatisfy { $0.currentPath != nil })
        }
    }

}

@Suite("Cleanup catalogue")
struct CleanupCatalogueTests {
    @Test("Scanner identifiers are unique, because settings and history persist them")
    func identifiersAreUnique() {
        let ids = CleanupCatalogue.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Every rule declares at least one root — a scanner with no root can reach nothing")
    func everyRuleHasRoots() {
        for rule in CleanupCatalogue.all {
            #expect(!rule.roots.isEmpty, "\(rule.id) has no roots")
        }
    }

    @Test("Every rule has title and explanation keys")
    func everyRuleIsDescribed() {
        for rule in CleanupCatalogue.all {
            #expect(!rule.titleKey.isEmpty)
            #expect(!rule.explanationKey.isEmpty)
        }
    }

    @Test("Scanners that need the helper are marked, so nothing promises what it cannot do")
    func helperScannersAreMarked() {
        #expect(CleanupCatalogue.systemCaches.requiresHelper)
        #expect(!CleanupCatalogue.userCaches.requiresHelper)
    }

    @Test("Emptying the Trash is the only permanent scanner — §4.1")
    func onlyTrashIsPermanent() {
        #expect(CleanupCatalogue.permanentScanners == [CleanupCatalogue.userTrash.id])
    }

    @Test("No rule reaches outside the user's home except the system scanner")
    func rootsStayInHome() {
        for rule in CleanupCatalogue.all where !rule.requiresHelper {
            for root in rule.roots {
                #expect(root.base == .home, "\(rule.id) reaches an absolute path without the helper")
            }
        }
    }
}
