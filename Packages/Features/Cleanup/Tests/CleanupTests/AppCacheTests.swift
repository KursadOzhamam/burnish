import Testing
import Foundation
import CoreKit
import ScanEngine
import SafetyKit
import SafetyKitMac
@testable import Cleanup

/// Application-specific cache folders: found whole, named by label, protected while in use.
@Suite("App caches", .serialized)
struct AppCacheTests {

    private func withHome(_ body: (URL) async throws -> Void) async throws {
        let home = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("BurnishAppCacheHome-\(UUID().uuidString)")
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

    private func scanner(_ rule: CleanupRule, home: URL, running: Set<String>) -> CleanupScanner {
        CleanupScanner(rule: rule, home: home, inspector: StaticRunningApplicationInspector(running))
    }

    @Test("A cache folder is one item, named by its label")
    func foundWholeWithLabel() async throws {
        try await withHome { home in
            try write("Library/Application Support/Figma/DesktopProfile/v43/Cache/a", in: home)
            try write("Library/Application Support/Figma/DesktopProfile/v43/Cache/b", in: home)

            let items = try await scanner(CleanupCatalogue.appCaches, home: home, running: [])
                .scan { _ in }

            #expect(items.count == 1)
            #expect(items.first?.displayName == "Figma")
            #expect(items.first?.isActionable == true)
        }
    }

    @Test("User data beside the cache is not offered")
    func neighboursNotOffered() async throws {
        try await withHome { home in
            try write("Library/Application Support/Figma/DesktopProfile/v43/Cache/a", in: home)
            try write("Library/Application Support/Figma/settings.json", in: home)
            try write("Library/Application Support/Figma/DesktopProfile/v43/IndexedDB/db", in: home)

            let items = try await scanner(CleanupCatalogue.appCaches, home: home, running: [])
                .scan { _ in }

            #expect(items.count == 1)
            #expect(items.allSatisfy { $0.url.lastPathComponent == "Cache" })
        }
    }

    @Test("A running application blocks its cache")
    func runningOwnerBlocks() async throws {
        try await withHome { home in
            try write("Library/Application Support/Claude/Cache/a", in: home)
            let items = try await scanner(
                CleanupCatalogue.appCaches, home: home, running: ["com.anthropic.claudefordesktop"]
            ).scan { _ in }
            #expect(items.allSatisfy { $0.blockedReason == .ownerRunning })
        }
    }

    @Test("Any Adobe application running blocks the shared media cache")
    func anyAdobeOwnerBlocks() async throws {
        try await withHome { home in
            try write("Library/Application Support/Adobe/Common/Media Cache Files/a", in: home)
            let items = try await scanner(
                CleanupCatalogue.adobeMediaCaches, home: home, running: ["com.adobe.Audition"]
            ).scan { _ in }
            #expect(!items.isEmpty)
            #expect(items.allSatisfy { $0.blockedReason == .ownerRunning })
        }
    }

    @Test("Adobe caches are never preselected")
    func adobeNotPreselected() async throws {
        try await withHome { home in
            try write("Library/Application Support/Adobe/Common/Peak Files/a", in: home)
            let items = try await scanner(CleanupCatalogue.adobeMediaCaches, home: home, running: [])
                .scan { _ in }
            #expect(items.defaultSelection().isEmpty)
        }
    }

    @Test("The cache folder can be removed through the safety layer, its parent cannot")
    func guardAllowsTargetOnly() async throws {
        try await withHome { home in
            let scanner = scanner(CleanupCatalogue.appCaches, home: home, running: [])
            let subject = PathGuard(
                allowedRoots: scanner.allowedRoots,
                allowedTargets: scanner.allowedTargets,
                home: home
            )
            let cache = home.appendingPathComponent("Library/Application Support/Claude/Cache")
            #expect(subject.isAllowed(cache))
            #expect(!subject.isAllowed(cache.deletingLastPathComponent()))
        }
    }

    @Test("Every app cache root declares an owner and a label")
    func everyRootDeclaresOwnerAndLabel() {
        for rule in [CleanupCatalogue.appCaches, CleanupCatalogue.adobeMediaCaches] {
            for root in rule.roots {
                #expect(!root.owners.isEmpty, "\(root.path) has no owner")
                #expect(root.label != nil, "\(root.path) has no label")
                #expect(!root.listsChildren)
            }
        }
    }
}

@Suite("Privacy scanners")
struct PrivacyCatalogueTests {
    @Test("Every privacy scanner is low confidence, so nothing is ever preselected")
    func neverPreselected() {
        for rule in CleanupCatalogue.Privacy.all { #expect(rule.confidence == .low, "\(rule.id)") }
    }

    @Test("Privacy removal goes to the Trash like everything else (§4.1)")
    func notPermanent() {
        for rule in CleanupCatalogue.Privacy.all { #expect(!CleanupCatalogue.permanentScanners.contains(rule.id)) }
    }

    @Test("Every browser file declares the browser that owns it, so an open browser blocks it")
    func ownersDeclared() {
        for rule in [CleanupCatalogue.Privacy.safari, CleanupCatalogue.Privacy.chromium] {
            for root in rule.roots { #expect(!root.owners.isEmpty, "\(root.path)") }
        }
    }

    @Test("A single history file is found, labelled, and blocked while its browser runs")
    func singleFile() async throws {
        let home = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishPriv-\(UUID().uuidString)")
        let folder = home.appendingPathComponent("Library/Application Support/Google/Chrome/Default")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 5_000).write(to: folder.appendingPathComponent("History"))
        defer {
            // Fixture teardown, not product code.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: home)
        }
        let closed = try await CleanupScanner(
            rule: CleanupCatalogue.Privacy.chromium, home: home, inspector: StaticRunningApplicationInspector([])
        ).scan { _ in }
        #expect(closed.map(\.displayName) == ["History"])
        #expect(closed.allSatisfy { $0.isActionable })
        let running = try await CleanupScanner(
            rule: CleanupCatalogue.Privacy.chromium, home: home, inspector: StaticRunningApplicationInspector(["com.google.Chrome"])
        ).scan { _ in }
        #expect(running.allSatisfy { $0.blockedReason == .ownerRunning })
    }
}
