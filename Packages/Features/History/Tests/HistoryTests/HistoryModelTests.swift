import Testing
import Foundation
import CoreKit
import ScanEngine
import SafetyKit
import SafetyKitMac
@testable import History

/// CLAUDE.md §4.7. The filesystem is never touched: restoring goes through a stub.
@Suite("HistoryModel")
@MainActor
struct HistoryModelTests {

    private final class StubRestorer: RestoringItems, @unchecked Sendable {
        var restoredIDs: [Int64] = []
        var failure: Error?
        var destination = URL(fileURLWithPath: "/Users/t/Library/Caches/app/file.bin")

        func restore(recordID: Int64) throws -> URL {
            if let failure { throw failure }
            restoredIDs.append(recordID)
            return destination
        }
    }

    private func seededStore() throws -> HistoryStore {
        let store = try HistoryStore()
        try store.record(
            DeletionReport(
                outcomes: [
                    DeletionOutcome(
                        item: ScanItem(
                            scanner: ScannerID("t"),
                            url: URL(fileURLWithPath: "/Users/t/Library/Caches/app/file.bin"),
                            size: .megabytes(5)
                        ),
                        result: .trashed(restoreURL: URL(fileURLWithPath: "/Users/t/.Trash/file.bin"))
                    ),
                    DeletionOutcome(
                        item: ScanItem(
                            scanner: ScannerID("t"),
                            url: URL(fileURLWithPath: "/Users/t/Library/Caches/gone.bin"),
                            size: .megabytes(1)
                        ),
                        result: .failed(message: "busy")
                    )
                ],
                mode: .trash
            )
        )
        return store
    }

    @Test("Reload fills the records and the reclaimed total")
    func reloadFillsRecords() throws {
        let model = HistoryModel(store: try seededStore(), restorer: StubRestorer())
        model.reload()

        #expect(model.records.count == 2)
        #expect(model.totalReclaimed == .megabytes(5), "the failed item must not count")
        #expect(model.restorableCount == 1)
    }

    @Test("Restoring reports success and asks the restorer for the right record")
    func restoreSucceeds() throws {
        let stub = StubRestorer()
        let model = HistoryModel(store: try seededStore(), restorer: stub)
        model.reload()

        let restorable = try #require(model.records.first { $0.canRestore })
        model.restore(restorable)

        #expect(stub.restoredIDs == [restorable.id])
        #expect(model.notice == .restored(name: "file.bin"))
    }

    @Test("A refusal is surfaced as a notice, not swallowed")
    func restoreRefusalIsShown() throws {
        let stub = StubRestorer()
        stub.failure = RestoreService.Failure.destinationOccupied("/Users/t/x")
        let model = HistoryModel(store: try seededStore(), restorer: stub)
        model.reload()

        model.restore(try #require(model.records.first { $0.canRestore }))

        #expect(model.notice == .failed(.destinationOccupied("/Users/t/x")))
        #expect(stub.restoredIDs.isEmpty)
    }

    @Test("An unexpected error becomes a move failure rather than a crash")
    func unexpectedErrorIsContained() throws {
        let stub = StubRestorer()
        stub.failure = CocoaError(.fileWriteNoPermission)
        let model = HistoryModel(store: try seededStore(), restorer: stub)
        model.reload()

        model.restore(try #require(model.records.first { $0.canRestore }))

        guard case .failed(.moveFailed) = model.notice else {
            Issue.record("expected a moveFailed notice, got \(String(describing: model.notice))")
            return
        }
    }

    @Test("Dismissing clears the notice")
    func dismissClearsNotice() throws {
        let stub = StubRestorer()
        let model = HistoryModel(store: try seededStore(), restorer: stub)
        model.reload()
        model.restore(try #require(model.records.first { $0.canRestore }))
        #expect(model.notice != nil)

        model.dismissNotice()
        #expect(model.notice == nil)
    }

    @Test("Without a log the model says so and does nothing")
    func unavailableModelIsInert() {
        let model = HistoryModel(store: nil)
        model.reload()

        #expect(!model.isAvailable)
        #expect(model.records.isEmpty)
        #expect(model.restorableCount == 0)
    }

    @Test("A record that was never saved cannot be restored")
    func recordWithoutIDIsIgnored() throws {
        let stub = StubRestorer()
        let model = HistoryModel(store: try seededStore(), restorer: stub)
        let unsaved = OperationRecord(
            performedAt: .now, path: "/x", displayName: "x", byteCount: 1,
            scannerID: "t", mode: .trash, outcome: .trashed, restorePath: "/t/x"
        )

        model.restore(unsaved)

        #expect(stub.restoredIDs.isEmpty)
        #expect(model.notice == nil)
    }
}
