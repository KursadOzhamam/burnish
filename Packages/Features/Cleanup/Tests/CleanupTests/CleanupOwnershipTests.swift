import Testing
import Foundation
import CoreKit
import ScanEngine
import SafetyKitMac
@testable import Cleanup

/// CLAUDE.md §4.5. Ownership must not depend on the path naming the application: Chrome's cache
/// lives under `Caches/Google/Chrome`, which contains no bundle identifier.
@Suite("Running owner detection", .serialized)
struct CleanupOwnershipTests {

    private func withHome(_ body: (URL) async throws -> Void) async throws {
        let home = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("BurnishOwnerHome-\(UUID().uuidString)")
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
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: 4_096).write(to: url)
    }

    private func scan(_ rule: CleanupRule, home: URL, running: Set<String>) async throws -> [ScanItem] {
        try await CleanupScanner(
            rule: rule,
            home: home,
            inspector: StaticRunningApplicationInspector(running)
        ).scan { _ in }
    }

    @Test("Chrome's cache is blocked while Chrome runs, though its path names no bundle id")
    func runningChromeBlocksItsCache() async throws {
        try await withHome { home in
            try write("Library/Caches/Google/Chrome/Default/Cache/data_0", in: home)

            let items = try await scan(
                CleanupCatalogue.browserCaches, home: home, running: ["com.google.Chrome"]
            )

            #expect(!items.isEmpty)
            #expect(items.allSatisfy { $0.blockedReason == .ownerRunning })
        }
    }

    @Test("The same cache is actionable when Chrome is closed")
    func closedChromeLeavesCacheActionable() async throws {
        try await withHome { home in
            try write("Library/Caches/Google/Chrome/Default/Cache/data_0", in: home)
            let items = try await scan(CleanupCatalogue.browserCaches, home: home, running: [])
            #expect(items.allSatisfy { $0.isActionable })
        }
    }

    @Test("A helper process of the owner counts as the owner running")
    func helperProcessCounts() async throws {
        try await withHome { home in
            try write("Library/Caches/Google/Chrome/Default/Cache/data_0", in: home)
            let items = try await scan(
                CleanupCatalogue.browserCaches, home: home, running: ["com.google.Chrome.helper"]
            )
            #expect(items.allSatisfy { $0.blockedReason == .ownerRunning })
        }
    }

    @Test("Another browser running does not block this one")
    func otherBrowserDoesNotBlock() async throws {
        try await withHome { home in
            try write("Library/Caches/Google/Chrome/Default/Cache/data_0", in: home)
            let items = try await scan(
                CleanupCatalogue.browserCaches, home: home, running: ["org.mozilla.firefox"]
            )
            #expect(items.allSatisfy { $0.isActionable })
        }
    }

    @Test("Every browser root declares its owner, so none relies on the path")
    func everyBrowserRootHasAnOwner() {
        for root in CleanupCatalogue.browserCaches.roots {
            #expect(root.owner != nil, "\(root.path) has no declared owner")
        }
    }

    @Test("Xcode device support and archives are listed but never preselected")
    func xcodeScannersAreNotPreselected() async throws {
        try await withHome { home in
            try write("Library/Developer/Xcode/iOS DeviceSupport/iPhone15,2 26.6 (23G71)/Symbols/a", in: home)
            try write("Library/Developer/Xcode/Archives/2026-09-30/App.xcarchive/Info.plist", in: home)

            let support = try await scan(CleanupCatalogue.xcodeDeviceSupport, home: home, running: [])
            let archives = try await scan(CleanupCatalogue.xcodeArchives, home: home, running: [])

            #expect(support.count == 1)
            #expect(archives.count == 1)
            #expect((support + archives).allSatisfy { !$0.isSelectedByDefault })
            #expect((support + archives).allSatisfy { $0.isActionable }, "listed and selectable by hand")
        }
    }

    @Test("Xcode running blocks its device support and archives")
    func runningXcodeBlocksItsFolders() async throws {
        try await withHome { home in
            try write("Library/Developer/Xcode/iOS DeviceSupport/iPhone15,2 26.6 (23G71)/Symbols/a", in: home)
            let items = try await scan(
                CleanupCatalogue.xcodeDeviceSupport, home: home, running: ["com.apple.dt.Xcode"]
            )
            #expect(items.allSatisfy { $0.blockedReason == .ownerRunning })
        }
    }
}
