import Testing
import Foundation
import CoreKit
import ScanEngine
import SafetyKit
@testable import SafetyKitMac

/// CLAUDE.md §4 and §9. The filesystem is never touched: trash and remove are injected, so a
/// bug in the service cannot delete anything on the machine running the suite.
@Suite("DeletionService")
struct DeletionServiceTests {
    private let scanner = ScannerID("test.cache")
    private let home = URL(fileURLWithPath: "/Users/tester")
    private var root: URL { home.appendingPathComponent("Library/Caches") }

    /// Records what the service asked the filesystem to do.
    private final class Recorder: @unchecked Sendable {
        var trashed: [URL] = []
        var removed: [URL] = []
        var trashError: Error?
        var removeError: Error?
        var missing: Set<String> = []
    }

    private func makeService(
        recorder: Recorder,
        running: Set<String> = [],
        history: HistoryStore? = nil,
        roots: [URL]? = nil
    ) -> DeletionService {
        DeletionService(
            guards: [scanner: PathGuard(allowedRoots: roots ?? [root], home: home)],
            inspector: StaticRunningApplicationInspector(running),
            history: history,
            trashItem: { url in
                if let error = recorder.trashError { throw error }
                recorder.trashed.append(url)
                return URL(fileURLWithPath: "/Users/tester/.Trash/\(url.lastPathComponent)")
            },
            removeItem: { url in
                if let error = recorder.removeError { throw error }
                recorder.removed.append(url)
            },
            fileExists: { !recorder.missing.contains($0.path) }
        )
    }

    private func item(_ relative: String, size: Int64 = 1_000) -> ScanItem {
        ScanItem(
            scanner: scanner,
            url: root.appendingPathComponent(relative),
            size: ByteCount(size)
        )
    }

    // MARK: Dry run

    @Test("Planning touches nothing — §4.6")
    func planIsInert() {
        let recorder = Recorder()
        let service = makeService(recorder: recorder)

        let plan = service.plan(for: [item("a"), item("b")], mode: .trash)

        #expect(plan.itemCount == 2)
        #expect(recorder.trashed.isEmpty)
        #expect(recorder.removed.isEmpty)
    }

    @Test("Items outside the scanner's root are skipped with a reason, not dropped")
    func outsideRootIsSkipped() {
        let service = makeService(recorder: Recorder())
        let outside = ScanItem(
            scanner: scanner,
            url: home.appendingPathComponent("Documents/thesis.pages"),
            size: .megabytes(5)
        )

        let plan = service.plan(for: [item("ok"), outside], mode: .trash)

        #expect(plan.itemCount == 1)
        #expect(plan.skipped.count == 1)
        #expect(plan.skipped.first?.displayName == "thesis.pages")
    }

    @Test("A scanner with no declared root can delete nothing")
    func unknownScannerIsRefused() {
        let service = makeService(recorder: Recorder())
        let foreign = ScanItem(
            scanner: ScannerID("not.registered"),
            url: root.appendingPathComponent("x"),
            size: .zero
        )

        let plan = service.plan(for: [foreign], mode: .trash)
        #expect(plan.isEmpty)
        #expect(plan.skipped.count == 1)
    }

    @Test("Files belonging to a running application are skipped — §4.5")
    func runningApplicationFilesAreSkipped() {
        let service = makeService(recorder: Recorder(), running: ["com.apple.Safari"])
        let safari = ScanItem(
            scanner: scanner,
            url: root.appendingPathComponent("com.apple.Safari/WebKitCache"),
            size: .megabytes(80)
        )

        let plan = service.plan(for: [safari, item("other")], mode: .trash)

        #expect(plan.itemCount == 1)
        #expect(plan.skipped.first?.blockedReason == .ownerRunning)
    }

    // MARK: Execution

    @Test("Trash is the default and items go to the Trash, not oblivion — §4.1")
    func trashModeUsesTrash() throws {
        let recorder = Recorder()
        let service = makeService(recorder: recorder)

        let report = try service.execute(service.plan(for: [item("a")], mode: .trash))

        #expect(recorder.trashed.count == 1)
        #expect(recorder.removed.isEmpty)
        #expect(report.restorable.count == 1)
        #expect(report.reclaimed.bytes == 1_000)
    }

    @Test("A permanent plan without explicit confirmation throws instead of deleting — §4.1")
    func permanentRequiresConfirmation() {
        let recorder = Recorder()
        let service = makeService(recorder: recorder)
        let plan = service.plan(for: [item("a")], mode: .permanent)

        #expect(throws: SafetyError.missingIrreversibleConfirmation) {
            try service.execute(plan)
        }
        #expect(recorder.removed.isEmpty)
        #expect(recorder.trashed.isEmpty)
    }

    @Test("A confirmed permanent plan deletes")
    func confirmedPermanentDeletes() throws {
        let recorder = Recorder()
        let service = makeService(recorder: recorder)
        let plan = service.plan(for: [item("a")], mode: .permanent)

        let report = try service.execute(plan, confirmedIrreversible: true)

        #expect(recorder.removed.count == 1)
        #expect(report.restorable.isEmpty)
    }

    @Test("One failure does not stop the run — §4.8")
    func failureDoesNotAbortTheRun() throws {
        let recorder = Recorder()
        recorder.trashError = CocoaError(.fileWriteNoPermission)
        let service = makeService(recorder: recorder)

        let report = try service.execute(
            service.plan(for: [item("a"), item("b"), item("c")], mode: .trash)
        )

        #expect(report.outcomes.count == 3)
        #expect(report.failures.count == 3)
        #expect(report.reclaimed == .zero)
    }

    @Test("An item that vanished between planning and execution is skipped, not counted")
    func vanishedItemIsNotCountedAsReclaimed() throws {
        let recorder = Recorder()
        recorder.missing = [root.appendingPathComponent("gone").path]
        let service = makeService(recorder: recorder)

        let report = try service.execute(
            service.plan(for: [item("gone"), item("here")], mode: .trash)
        )

        #expect(report.reclaimed.bytes == 1_000)
        #expect(report.skipped.count == 1)
    }

    @Test("Skipped items are reported in the result, not silently discarded")
    func skippedItemsAppearInTheReport() throws {
        let service = makeService(recorder: Recorder(), running: ["com.example.app"])
        let plan = service.plan(
            for: [
                item("fine"),
                ScanItem(
                    scanner: scanner,
                    url: root.appendingPathComponent("com.example.app/data"),
                    size: .megabytes(3)
                )
            ],
            mode: .trash
        )

        let report = try service.execute(plan)

        #expect(report.outcomes.count == 2)
        #expect(report.skipped.count == 1)
    }

    @Test("Validation runs again at deletion time, not only at planning time — §4.4")
    func revalidatesBeforeActing() throws {
        let recorder = Recorder()
        // A plan built against a wide root, then executed by a service whose guard is narrow:
        // stands in for a path that stopped being acceptable after the plan was approved.
        let planningService = makeService(recorder: recorder, roots: [home])
        let plan = planningService.plan(
            for: [ScanItem(
                scanner: scanner,
                // Inside home but outside ~/Library/Caches, and not on the protected list —
                // so the wide guard accepts it and the narrow one must not.
                url: home.appendingPathComponent("Library/Application Support/Example/blob"),
                size: .megabytes(1)
            )],
            mode: .trash
        )
        #expect(plan.itemCount == 1, "fixture should produce an actionable plan")

        let executingService = makeService(recorder: recorder)
        let report = try executingService.execute(plan)

        #expect(recorder.trashed.isEmpty)
        #expect(report.reclaimed == .zero)
        #expect(report.hasFailures || !report.skipped.isEmpty)
    }

    @Test("An empty plan is a no-op")
    func emptyPlanDoesNothing() throws {
        let recorder = Recorder()
        let service = makeService(recorder: recorder)

        let report = try service.execute(service.plan(for: [], mode: .trash))

        #expect(report.outcomes.isEmpty)
        #expect(report.reclaimed == .zero)
        #expect(recorder.trashed.isEmpty)
    }

    // MARK: History

    @Test("Every run is written to the operation log, including skips and failures — §4.7")
    func runIsRecorded() throws {
        let recorder = Recorder()
        recorder.missing = [root.appendingPathComponent("gone").path]
        let history = try HistoryStore()
        let service = makeService(recorder: recorder, running: [], history: history)

        _ = try service.execute(
            service.plan(for: [item("a"), item("gone")], mode: .trash)
        )

        #expect(try history.count() == 2)
        #expect(try history.restorable().count == 1)
        #expect(try history.totalReclaimed().bytes == 1_000)
    }

    @Test("Restored items stop being offered")
    func restoringClearsTheOffer() throws {
        let history = try HistoryStore()
        let service = makeService(recorder: Recorder(), history: history)

        _ = try service.execute(service.plan(for: [item("a")], mode: .trash))

        let restorable = try history.restorable()
        #expect(restorable.count == 1)

        try history.markRestored(id: #require(restorable.first?.id))
        #expect(try history.restorable().isEmpty)
    }
}

/// Regression cover for the app offering to trash the folder it is running from.
@Suite("Running process protection")
struct RunningProcessProtectionTests {
    private let scanner = ScannerID("test.dev")
    private let home = URL(fileURLWithPath: "/Users/tester")
    private var root: URL { home.appendingPathComponent("Library/Developer/Xcode/DerivedData") }

    private func service(runningFrom bundle: URL) -> DeletionService {
        DeletionService(
            guards: [scanner: PathGuard(allowedRoots: [root], home: home)],
            inspector: StaticRunningApplicationInspector(),
            history: nil,
            protectedProcessPaths: [bundle],
            trashItem: { _ in nil },
            removeItem: { _ in },
            fileExists: { _ in true }
        )
    }

    private func item(_ relative: String) -> ScanItem {
        ScanItem(scanner: scanner, url: root.appendingPathComponent(relative), size: .megabytes(700))
    }

    @Test("A folder containing the running app's bundle is refused, however it is named")
    func buildFolderOfTheRunningAppIsRefused() {
        let bundle = root.appendingPathComponent("Burnish-abc123/Build/Products/Debug/Burnish.app")
        let subject = service(runningFrom: bundle)

        let plan = subject.plan(for: [item("Burnish-abc123")], mode: .trash)

        #expect(plan.isEmpty)
        #expect(plan.skipped.first?.blockedReason == .ownerRunning)
    }

    @Test("Other build folders beside it are still offered")
    func siblingsAreStillOffered() {
        let bundle = root.appendingPathComponent("Burnish-abc123/Build/Products/Debug/Burnish.app")
        let subject = service(runningFrom: bundle)

        let plan = subject.plan(
            for: [item("Burnish-abc123"), item("OtherProject-def456")],
            mode: .trash
        )

        #expect(plan.itemCount == 1)
        #expect(plan.items.first?.displayName == "OtherProject-def456")
    }

    @Test("It is refused again at execution time, not only when planned")
    func refusedAtExecutionToo() throws {
        let bundle = root.appendingPathComponent("Burnish-abc123/Build/Products/Debug/Burnish.app")
        let subject = service(runningFrom: bundle)
        // Plan against a service that does not know about the running bundle...
        let permissive = service(runningFrom: URL(fileURLWithPath: "/nowhere"))
        let plan = permissive.plan(for: [item("Burnish-abc123")], mode: .trash)
        #expect(plan.itemCount == 1, "fixture should be actionable to the permissive service")

        // ...and execute it with one that does.
        let report = try subject.execute(plan)
        #expect(report.reclaimed == .zero)
        #expect(report.skipped.count == 1)
    }
}

