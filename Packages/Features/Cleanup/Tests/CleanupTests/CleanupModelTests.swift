import Testing
import Foundation
import CoreKit
import ScanEngine
import SafetyKit
import SafetyKitMac
@testable import Cleanup

/// CLAUDE.md §9 asks for state-transition tests on the cleanup flow, and §4.6 for proof that
/// nothing happens before approval.
@Suite("CleanupModel", .serialized)
@MainActor
struct CleanupModelTests {

    private func withHome(_ body: (URL) async throws -> Void) async throws {
        let home = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("BurnishModel-\(UUID().uuidString)")
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
        try Data(repeating: 0x44, count: bytes).write(to: url)
        return url
    }

    private func model(home: URL, running: Set<String> = []) -> CleanupModel {
        CleanupModel(
            scanners: [
                CleanupScanner(
                    rule: CleanupCatalogue.userCaches,
                    home: home,
                    inspector: StaticRunningApplicationInspector(running)
                )
            ]
        )
    }

    /// Waits for the model to leave its busy phases.
    private func settle(_ subject: CleanupModel) async throws {
        for _ in 0..<200 where subject.phase.isBusy {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("A fresh model is idle and has found nothing")
    func startsIdle() async throws {
        try await withHome { home in
            let subject = model(home: home)
            #expect(!subject.phase.isBusy)
            #expect(subject.categories.isEmpty)
            #expect(subject.selectedItems.isEmpty)
        }
    }

    @Test("Scanning moves to review and preselects high-confidence findings")
    func scanningFillsCategories() async throws {
        try await withHome { home in
            try write(4_096, to: home.appendingPathComponent("Library/Caches/com.a/x"))
            try write(4_096, to: home.appendingPathComponent("Library/Caches/com.b/y"))

            let subject = model(home: home)
            subject.scan()
            try await settle(subject)

            guard case .reviewing = subject.phase else {
                Issue.record("expected review, got \(subject.phase)")
                return
            }
            #expect(subject.categories.count == 1)
            #expect(subject.selectedItems.count == 2)
            #expect(subject.selectedSize.bytes > 0)
        }
    }

    @Test("Nothing is deleted by scanning or by building a plan — §4.6")
    func planningTouchesNothing() async throws {
        try await withHome { home in
            let file = try write(4_096, to: home.appendingPathComponent("Library/Caches/com.a/x"))

            let subject = model(home: home)
            subject.scan()
            try await settle(subject)
            subject.prepareConfirmation()

            #expect(subject.pendingPlan != nil)
            #expect(FileManager.default.fileExists(atPath: file.path), "the dry run must not delete")
        }
    }

    @Test("Blocked items cannot be selected, even by select-all")
    func blockedItemsStayUnselected() async throws {
        try await withHome { home in
            try write(4_096, to: home.appendingPathComponent("Library/Caches/com.a/x"))

            let subject = CleanupModel(
                scanners: [
                    CleanupScanner(
                        rule: CleanupCatalogue.systemCaches,  // always needs the helper
                        home: home,
                        inspector: StaticRunningApplicationInspector()
                    )
                ]
            )
            subject.scan()
            try await settle(subject)

            for category in subject.categories {
                subject.setSelection(true, in: category)
            }
            #expect(subject.selectedItems.isEmpty, "a blocked item must never become selected")
        }
    }

    @Test("Confirming a plan the model is not holding does nothing")
    func staleePlanIsIgnored() async throws {
        try await withHome { home in
            let file = try write(4_096, to: home.appendingPathComponent("Library/Caches/com.a/x"))

            let subject = model(home: home)
            subject.scan()
            try await settle(subject)

            // A plan the user was never shown.
            let forged = DeletionPlan(
                items: [ScanItem(
                    scanner: CleanupCatalogue.userCaches.id,
                    url: file,
                    size: .megabytes(1)
                )],
                mode: .permanent
            )
            subject.confirm(forged)

            #expect(FileManager.default.fileExists(atPath: file.path))
            #expect(!subject.phase.isBusy)
        }
    }

    @Test("Deselecting everything disables the review step")
    func emptySelectionProducesNoPlan() async throws {
        try await withHome { home in
            try write(4_096, to: home.appendingPathComponent("Library/Caches/com.a/x"))

            let subject = model(home: home)
            subject.scan()
            try await settle(subject)

            for category in subject.categories {
                subject.setSelection(false, in: category)
            }
            subject.prepareConfirmation()

            #expect(subject.selectedItems.isEmpty)
            #expect(subject.pendingPlan == nil)
        }
    }

    @Test("Cancelling a scan returns to idle")
    func cancellingReturnsToIdle() async throws {
        try await withHome { home in
            for index in 0..<40 {
                try write(2_048, to: home.appendingPathComponent("Library/Caches/com.\(index)/x"))
            }
            let subject = model(home: home)
            subject.scan()
            subject.cancel()

            #expect(!subject.phase.isBusy)
        }
    }

    @Test("Reset clears findings and selection")
    func resetClearsState() async throws {
        try await withHome { home in
            try write(4_096, to: home.appendingPathComponent("Library/Caches/com.a/x"))
            let subject = model(home: home)
            subject.scan()
            try await settle(subject)
            subject.reset()

            #expect(subject.categories.isEmpty)
            #expect(subject.selection.isEmpty)
            #expect(subject.pendingPlan == nil)
        }
    }

    @Test("Emptying the Trash is planned as permanent, everything else as a move to the Trash")
    func trashScannerPlansPermanentDeletion() async throws {
        try await withHome { home in
            try write(4_096, to: home.appendingPathComponent(".Trash/old.bin"))

            let subject = CleanupModel(
                scanners: [
                    CleanupScanner(
                        rule: CleanupCatalogue.userTrash,
                        home: home,
                        inspector: StaticRunningApplicationInspector()
                    )
                ]
            )
            subject.scan()
            try await settle(subject)
            for category in subject.categories {
                subject.setSelection(true, in: category)
            }
            subject.prepareConfirmation()

            let plan = try #require(subject.pendingPlan)
            #expect(plan.mode == .permanent)
            #expect(plan.requiresExtraConfirmation)
        }
    }

    @Test("Anything the safety layer refuses is already blocked on the review screen")
    func refusalsAreVisibleBeforeConfirmation() async throws {
        try await withHome { home in
            try write(4_096, to: home.appendingPathComponent("Library/Caches/com.a/x"))

            let subject = model(home: home)
            subject.scan()
            try await settle(subject)

            // Whatever the review list shows as selected must survive planning unchanged, or
            // the sheet would quietly disagree with the screen the user just approved.
            subject.prepareConfirmation()
            let plan = try #require(subject.pendingPlan)
            #expect(plan.itemCount == subject.selectedItems.count)
            #expect(plan.totalSize == subject.selectedSize)
        }
    }
}
