import Testing
import Foundation
import CoreKit
import ScanEngine
import SafetyKit
@testable import SafetyKitMac

/// Exercises the real `FileManager` wiring that the unit tests inject around.
///
/// Everything happens inside a disposable directory under `/private/tmp` that the test creates
/// and removes; no system folder and no folder of the user's is touched (CLAUDE.md §9). The
/// trash case cleans up after itself so the suite leaves nothing in the user's Trash.
@Suite("DeletionService integration", .serialized)
struct DeletionIntegrationTests {
    private let scanner = ScannerID("integration")

    private func withTemporaryRoot(_ body: (URL) throws -> Void) throws {
        let root = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("BurnishDeletion-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Fixture teardown, not product code: removes only the directory this test created.
        // swiftlint:disable:next no_direct_remove_item
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func makeFile(in root: URL, named name: String, bytes: Int = 64) throws -> ScanItem {
        let url = root.appendingPathComponent(name)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return ScanItem(scanner: scanner, url: url, size: ByteCount(Int64(bytes)))
    }

    private func service(root: URL, history: HistoryStore? = nil) -> DeletionService {
        DeletionService(
            guards: [scanner: PathGuard(allowedRoots: [root])],
            inspector: StaticRunningApplicationInspector(),
            history: history
        )
    }

    @Test("Permanent deletion really removes the file through FileManager")
    func permanentDeletionRemovesTheFile() throws {
        try withTemporaryRoot { root in
            let item = try makeFile(in: root, named: "scratch.bin")
            let subject = service(root: root)

            #expect(FileManager.default.fileExists(atPath: item.url.path))

            let report = try subject.execute(
                subject.plan(for: [item], mode: .permanent),
                confirmedIrreversible: true
            )

            #expect(!FileManager.default.fileExists(atPath: item.url.path))
            #expect(report.reclaimed.bytes == 64)
            #expect(!report.hasFailures)
        }
    }

    @Test("Trashing returns a restore location, and the file leaves its original path")
    func trashingReturnsARestoreLocation() throws {
        try withTemporaryRoot { root in
            let item = try makeFile(in: root, named: "trashable.bin")
            let subject = service(root: root)

            let report = try subject.execute(subject.plan(for: [item], mode: .trash))

            #expect(!FileManager.default.fileExists(atPath: item.url.path))
            let restored = try #require(report.restorable.first)
            guard case .trashed(let restoreURL) = restored.result else {
                Issue.record("expected a trashed outcome")
                return
            }
            let location = try #require(restoreURL)
            #expect(FileManager.default.fileExists(atPath: location.path))

            // Leave the user's Trash as we found it.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: location)
        }
    }

    @Test("A protected path is refused even when it really exists on disk")
    func protectedPathIsRefusedForReal() throws {
        // /private/var/db exists on every Mac; the guard must refuse it rather than act.
        let subject = DeletionService(
            guards: [scanner: PathGuard(allowedRoots: [URL(fileURLWithPath: "/")])],
            inspector: StaticRunningApplicationInspector()
        )
        let item = ScanItem(
            scanner: scanner,
            url: URL(fileURLWithPath: "/private/var/db/dslocal"),
            size: .megabytes(1)
        )

        let plan = subject.plan(for: [item], mode: .trash)
        let report = try subject.execute(plan)

        // Refused at planning time and reported accurately as protected, not as a user exclusion.
        #expect(plan.isEmpty)
        #expect(plan.skipped.first?.blockedReason == .protectedPath)
        #expect(report.reclaimed == .zero)
        #expect(report.skipped.count == 1)
        #expect(FileManager.default.fileExists(atPath: "/private/var/db"))
    }

    @Test("A real run lands in the operation log with a usable restore path")
    func realRunIsLogged() throws {
        try withTemporaryRoot { root in
            let history = try HistoryStore()
            let item = try makeFile(in: root, named: "logged.bin", bytes: 128)
            let subject = service(root: root, history: history)

            let report = try subject.execute(subject.plan(for: [item], mode: .trash))

            let logged = try #require(try history.restorable().first)
            #expect(logged.byteCount == 128)
            #expect(logged.canRestore)
            #expect(try history.totalReclaimed().bytes == 128)

            if case .trashed(let url) = try #require(report.restorable.first).result, let url {
                // swiftlint:disable:next no_direct_remove_item
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

@Suite("Inspector and protected roots")
struct InspectorTests {
    @Test("The live inspector reads running applications without throwing")
    func liveInspectorWorks() {
        let subject = RunningApplicationInspector()
        // The test host itself is running, so this is non-empty in practice; the assertion that
        // matters is that reading NSWorkspace is safe to call from here.
        _ = subject.runningBundleIdentifiers()
    }

    @Test("Ownership is matched on reverse-DNS folder names, not app names")
    func ownershipMatchesBundleFolders() {
        let subject = StaticRunningApplicationInspector(["com.example.app"])

        let owned = URL(fileURLWithPath: "/Users/t/Library/Containers/com.example.app/Data/x")
        #expect(subject.owningBundleIdentifier(of: owned) == "com.example.app")

        let unrelated = URL(fileURLWithPath: "/Users/t/Library/Caches/Example App/x")
        #expect(subject.owningBundleIdentifier(of: unrelated) == nil)
    }

    @Test("Nothing is owned when nothing is running")
    func noRunningAppsMeansNoOwnership() {
        let subject = StaticRunningApplicationInspector()
        let url = URL(fileURLWithPath: "/Users/t/Library/Containers/com.example.app/x")
        #expect(subject.owningBundleIdentifier(of: url) == nil)
    }

    @Test("Absolute protected roots expand the home-relative entries")
    func absoluteRootsIncludeHomeEntries() {
        let home = URL(fileURLWithPath: "/Users/tester")
        let roots = ProtectedPaths.absoluteRoots(home: home)

        #expect(roots.contains("/System"))
        #expect(roots.contains("/Users/tester/Documents"))
        #expect(roots.contains("/Users/tester/.ssh"))
        #expect(roots.count == ProtectedPaths.systemRoots.count + ProtectedPaths.homeRelative.count)
    }
}
