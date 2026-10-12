import Testing
import Foundation
import CoreKit
import ScanEngine
@testable import SafetyKit

@Suite("DeletionPlan")
struct DeletionPlanTests {
    private let scanner = ScannerID("test")

    private func item(
        _ name: String,
        size: Int64 = 100,
        blocked: ScanItem.BlockedReason? = nil,
        children: [ScanItem] = []
    ) -> ScanItem {
        ScanItem(
            scanner: scanner,
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            size: ByteCount(size),
            children: children,
            blockedReason: blocked
        )
    }

    @Test("Blocked items cannot enter a plan even when passed in")
    func blockedItemsAreRoutedToSkipped() {
        let plan = DeletionPlan(
            items: [item("ok"), item("busy", blocked: .ownerRunning)],
            mode: .trash
        )
        #expect(plan.itemCount == 1)
        #expect(plan.skipped.count == 1)
        #expect(plan.items.allSatisfy { $0.isActionable })
    }

    @Test("Total size includes nested children")
    func totalSizeIncludesChildren() {
        let plan = DeletionPlan(items: [item("a", size: 100, children: [item("b", size: 50)])], mode: .trash)
        #expect(plan.totalSize.bytes == 150)
    }

    @Test("Skipped items do not count toward the total")
    func skippedDoesNotCount() {
        let plan = DeletionPlan(
            items: [item("a", size: 100), item("b", size: 900, blocked: .needsHelper)],
            mode: .trash
        )
        #expect(plan.totalSize.bytes == 100)
    }

    @Test("Permanent mode demands extra confirmation, trash does not")
    func extraConfirmationOnlyForPermanent() {
        #expect(DeletionPlan(items: [item("a")], mode: .permanent).requiresExtraConfirmation)
        #expect(!DeletionPlan(items: [item("a")], mode: .trash).requiresExtraConfirmation)
    }

    @Test("An empty permanent plan needs no confirmation")
    func emptyPlanNeedsNoConfirmation() {
        let plan = DeletionPlan(items: [], mode: .permanent)
        #expect(plan.isEmpty)
        #expect(!plan.requiresExtraConfirmation)
    }

    @Test("Trash is the default mode and is reversible")
    func defaultModeIsTrash() {
        #expect(DeletionMode.default == .trash)
        #expect(!DeletionMode.trash.isIrreversible)
        #expect(DeletionMode.permanent.isIrreversible)
    }
}

@Suite("DeletionReport")
struct DeletionReportTests {
    private func item(_ size: Int64) -> ScanItem {
        ScanItem(scanner: ScannerID("t"), url: URL(fileURLWithPath: "/tmp/x"), size: ByteCount(size))
    }

    @Test("Reclaimed space counts only items actually removed")
    func reclaimedExcludesFailuresAndSkips() {
        let report = DeletionReport(
            outcomes: [
                DeletionOutcome(item: item(100), result: .trashed(restoreURL: URL(fileURLWithPath: "/t"))),
                DeletionOutcome(item: item(200), result: .deleted),
                DeletionOutcome(item: item(400), result: .failed(message: "busy")),
                DeletionOutcome(item: item(800), result: .skipped(.ownerRunning))
            ],
            mode: .trash
        )
        #expect(report.reclaimed.bytes == 300)
        #expect(report.failures.count == 1)
        #expect(report.skipped.count == 1)
        #expect(report.hasFailures)
    }

    @Test("Only trashed items with a restore URL are restorable")
    func restorability() {
        let report = DeletionReport(
            outcomes: [
                DeletionOutcome(item: item(1), result: .trashed(restoreURL: URL(fileURLWithPath: "/t"))),
                DeletionOutcome(item: item(1), result: .trashed(restoreURL: nil)),
                DeletionOutcome(item: item(1), result: .deleted)
            ],
            mode: .trash
        )
        #expect(report.restorable.count == 1)
    }

    @Test("An all-failure run reclaims nothing and reports no success")
    func allFailures() {
        let report = DeletionReport(
            outcomes: [DeletionOutcome(item: item(999), result: .failed(message: "nope"))],
            mode: .trash
        )
        #expect(report.reclaimed == .zero)
        #expect(report.hasFailures)
    }
}

/// Guards the total against double counting — CLAUDE.md §10.4.
@Suite("Plan de-duplication")
struct PlanNestingTests {
    private let scanner = ScannerID("test")

    private func item(_ path: String, size: Int64 = 1_000) -> ScanItem {
        ScanItem(scanner: scanner, url: URL(fileURLWithPath: path), size: ByteCount(size))
    }

    @Test("An item inside another item is counted once, not twice")
    func nestedItemIsCountedOnce() {
        let plan = DeletionPlan(
            items: [
                item("/Users/t/Library/Caches/Brave", size: 1_000),
                item("/Users/t/Library/Caches/Brave/Default", size: 1_000)
            ],
            mode: .trash
        )
        #expect(plan.itemCount == 1)
        #expect(plan.totalSize.bytes == 1_000, "the child's bytes are already inside the parent")
        #expect(plan.skipped.count == 1)
    }

    @Test("The parent is kept and the child dropped, whatever order they arrive in")
    func parentWinsRegardlessOfOrder() {
        let child = item("/a/b/c")
        let parent = item("/a/b")

        for ordering in [[child, parent], [parent, child]] {
            let plan = DeletionPlan(items: ordering, mode: .trash)
            #expect(plan.items.first?.url.path == "/a/b")
        }
    }

    @Test("Siblings are both kept")
    func siblingsAreUnaffected() {
        let plan = DeletionPlan(
            items: [item("/a/b", size: 10), item("/a/c", size: 20)],
            mode: .trash
        )
        #expect(plan.itemCount == 2)
        #expect(plan.totalSize.bytes == 30)
    }

    @Test("A name that merely shares a prefix is not treated as nested")
    func prefixCollisionIsNotNesting() {
        let plan = DeletionPlan(
            items: [item("/a/cache"), item("/a/cache-old")],
            mode: .trash
        )
        #expect(plan.itemCount == 2)
    }

    @Test("Deep nesting collapses to the outermost item")
    func deepNestingCollapses() {
        let plan = DeletionPlan(
            items: [item("/a"), item("/a/b"), item("/a/b/c"), item("/a/b/c/d")],
            mode: .trash
        )
        #expect(plan.itemCount == 1)
        #expect(plan.items.first?.url.path == "/a")
        #expect(plan.skipped.count == 3)
    }

    @Test("Containment is computed by component, not by string prefix")
    func containmentByComponent() {
        #expect(DeletionPlan.path(URL(fileURLWithPath: "/a/b/c"), isInside: URL(fileURLWithPath: "/a/b")))
        #expect(!DeletionPlan.path(URL(fileURLWithPath: "/a/bc"), isInside: URL(fileURLWithPath: "/a/b")))
        #expect(!DeletionPlan.path(URL(fileURLWithPath: "/a/b"), isInside: URL(fileURLWithPath: "/a/b")))
    }
}
