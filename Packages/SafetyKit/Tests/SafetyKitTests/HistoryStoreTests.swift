import Testing
import Foundation
import CoreKit
import ScanEngine
@testable import SafetyKit

/// CLAUDE.md §4.7. Every store here is in-memory; nothing is written to disk.
@Suite("HistoryStore")
struct HistoryStoreTests {
    private let scanner = ScannerID("test")

    private func item(_ name: String, size: Int64 = 100) -> ScanItem {
        ScanItem(
            scanner: scanner,
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            size: ByteCount(size)
        )
    }

    private func store() throws -> HistoryStore { try HistoryStore() }

    @Test("A fresh store is empty and reports nothing reclaimed")
    func freshStoreIsEmpty() throws {
        let subject = try store()
        #expect(try subject.count() == 0)
        #expect(try subject.recent().isEmpty)
        #expect(try subject.totalReclaimed() == .zero)
    }

    @Test("Recording a report writes one row per outcome, failures included — §4.8")
    func everyOutcomeIsRecorded() throws {
        let subject = try store()
        let report = DeletionReport(
            outcomes: [
                DeletionOutcome(item: item("a"), result: .trashed(restoreURL: URL(fileURLWithPath: "/t/a"))),
                DeletionOutcome(item: item("b"), result: .deleted),
                DeletionOutcome(item: item("c"), result: .failed(message: "busy")),
                DeletionOutcome(item: item("d"), result: .skipped(.ownerRunning))
            ],
            mode: .trash
        )

        try subject.record(report)

        #expect(try subject.count() == 4)
        let failures = try subject.recent().filter { $0.outcome == .failed }
        #expect(failures.first?.failureMessage == "busy")
    }

    @Test("Reclaimed total counts only what was really removed — §10.4")
    func reclaimedExcludesFailuresAndSkips() throws {
        let subject = try store()
        try subject.record(
            DeletionReport(
                outcomes: [
                    DeletionOutcome(item: item("a", size: 100), result: .deleted),
                    DeletionOutcome(item: item("b", size: 200),
                                    result: .trashed(restoreURL: URL(fileURLWithPath: "/t/b"))),
                    DeletionOutcome(item: item("c", size: 400), result: .failed(message: "x")),
                    DeletionOutcome(item: item("d", size: 800), result: .skipped(.needsHelper))
                ],
                mode: .trash
            )
        )
        #expect(try subject.totalReclaimed().bytes == 300)
    }

    @Test("Only trashed items with a restore path are restorable")
    func restorableRequiresATrashLocation() throws {
        let subject = try store()
        try subject.record(
            DeletionReport(
                outcomes: [
                    DeletionOutcome(item: item("a"), result: .trashed(restoreURL: URL(fileURLWithPath: "/t/a"))),
                    DeletionOutcome(item: item("b"), result: .trashed(restoreURL: nil)),
                    DeletionOutcome(item: item("c"), result: .deleted)
                ],
                mode: .trash
            )
        )
        #expect(try subject.restorable().count == 1)
    }

    @Test("A restored item is not offered again")
    func markRestoredIsIdempotentFromTheUIPerspective() throws {
        let subject = try store()
        try subject.record(
            DeletionReport(
                outcomes: [DeletionOutcome(item: item("a"), result: .trashed(restoreURL: URL(fileURLWithPath: "/t/a")))],
                mode: .trash
            )
        )
        let id = try #require(try subject.restorable().first?.id)

        try subject.markRestored(id: id)
        #expect(try subject.restorable().isEmpty)

        // The row itself stays: the history is a log, not a to-do list.
        #expect(try subject.count() == 1)
        #expect(try subject.record(id: id)?.restoredAt != nil)
    }

    @Test("Recent orders newest first")
    func recentIsNewestFirst() throws {
        let subject = try store()
        let base = Date(timeIntervalSince1970: 1_000_000)
        for offset in 0..<5 {
            try subject.record(
                OperationRecord(
                    performedAt: base.addingTimeInterval(Double(offset) * 60),
                    path: "/tmp/\(offset)",
                    displayName: "\(offset)",
                    byteCount: 10,
                    scannerID: scanner.rawValue,
                    mode: .trash,
                    outcome: .trashed
                )
            )
        }
        let recent = try subject.recent()
        #expect(recent.first?.displayName == "4")
        #expect(recent.last?.displayName == "0")
    }

    @Test("Recent respects the limit")
    func recentRespectsLimit() throws {
        let subject = try store()
        for index in 0..<10 {
            try subject.record(
                OperationRecord(
                    performedAt: .now,
                    path: "/tmp/\(index)",
                    displayName: "\(index)",
                    byteCount: 1,
                    scannerID: scanner.rawValue,
                    mode: .trash,
                    outcome: .trashed
                )
            )
        }
        #expect(try subject.recent(limit: 3).count == 3)
    }

    @Test("History can be filtered by scanner")
    func filterByScanner() throws {
        let subject = try store()
        for name in ["cleanup.caches", "files.duplicates", "cleanup.caches"] {
            try subject.record(
                OperationRecord(
                    performedAt: .now,
                    path: "/tmp/x",
                    displayName: "x",
                    byteCount: 1,
                    scannerID: name,
                    mode: .trash,
                    outcome: .trashed
                )
            )
        }
        #expect(try subject.operations(scannerID: ScannerID("cleanup.caches")).count == 2)
        #expect(try subject.operations(scannerID: ScannerID("files.duplicates")).count == 1)
    }

    @Test("Pruning removes only entries older than the cutoff")
    func pruningRespectsTheCutoff() throws {
        let subject = try store()
        let old = Date(timeIntervalSince1970: 0)
        let recent = Date()
        for date in [old, old, recent] {
            try subject.record(
                OperationRecord(
                    performedAt: date,
                    path: "/tmp/x",
                    displayName: "x",
                    byteCount: 1,
                    scannerID: scanner.rawValue,
                    mode: .trash,
                    outcome: .trashed
                )
            )
        }
        let removed = try subject.prune(before: recent.addingTimeInterval(-60))
        #expect(removed == 2)
        #expect(try subject.count() == 1)
    }

    @Test("Records carry the platform, so a later iOS companion can share the log — §12.3")
    func platformIsRecorded() throws {
        let subject = try store()
        try subject.record(
            DeletionReport(
                outcomes: [DeletionOutcome(item: item("a"), result: .deleted)],
                mode: .permanent
            )
        )
        #expect(try subject.recent().first?.platform == OperationRecord.currentPlatform)
    }

    @Test("The mode is preserved, so the history can say how something went")
    func modeIsPreserved() throws {
        let subject = try store()
        try subject.record(
            DeletionReport(
                outcomes: [DeletionOutcome(item: item("a"), result: .deleted)],
                mode: .permanent
            )
        )
        #expect(try subject.recent().first?.mode == .permanent)
    }

    @Test("A log survives being reopened from disk")
    func persistsAcrossReopen() throws {
        let url = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("BurnishHistory-\(UUID().uuidString).sqlite")
        // Fixture teardown: a database file this test created.
        // swiftlint:disable:next no_direct_remove_item
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let first = try HistoryStore(url: url)
            try first.record(
                DeletionReport(
                    outcomes: [DeletionOutcome(item: item("a", size: 42), result: .deleted)],
                    mode: .permanent
                )
            )
        }

        let second = try HistoryStore(url: url)
        #expect(try second.count() == 1)
        #expect(try second.totalReclaimed().bytes == 42)
    }
}

@Suite("OperationRecord")
struct OperationRecordTests {
    @Test("canRestore requires a trashed outcome, a path, and no prior restore")
    func canRestoreRules() {
        func make(
            outcome: OperationRecord.Outcome,
            restorePath: String?,
            restoredAt: Date?
        ) -> OperationRecord {
            OperationRecord(
                performedAt: .now,
                path: "/tmp/x",
                displayName: "x",
                byteCount: 1,
                scannerID: "s",
                mode: .trash,
                outcome: outcome,
                restorePath: restorePath,
                restoredAt: restoredAt
            )
        }

        #expect(make(outcome: .trashed, restorePath: "/t/x", restoredAt: nil).canRestore)
        #expect(!make(outcome: .trashed, restorePath: nil, restoredAt: nil).canRestore)
        #expect(!make(outcome: .trashed, restorePath: "/t/x", restoredAt: .now).canRestore)
        #expect(!make(outcome: .deleted, restorePath: "/t/x", restoredAt: nil).canRestore)
        #expect(!make(outcome: .failed, restorePath: "/t/x", restoredAt: nil).canRestore)
    }
}
