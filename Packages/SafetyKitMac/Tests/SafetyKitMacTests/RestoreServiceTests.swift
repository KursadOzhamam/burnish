import Testing
import Foundation
import CoreKit
import ScanEngine
import SafetyKit
@testable import SafetyKitMac

/// CLAUDE.md §4.7 restore behaviour. Filesystem effects are injected.
@Suite("RestoreService")
struct RestoreServiceTests {
    private final class Recorder: @unchecked Sendable {
        var moves: [(from: URL, to: URL)] = []
        var existing: Set<String> = []
        var moveError: Error?
        var createdDirectories: [URL] = []
    }

    private func makeService(history: HistoryStore, recorder: Recorder) -> RestoreService {
        RestoreService(
            history: history,
            moveItem: { from, to in
                if let error = recorder.moveError { throw error }
                recorder.moves.append((from, to))
            },
            fileExists: { recorder.existing.contains($0.path) },
            createDirectory: { recorder.createdDirectories.append($0) }
        )
    }

    private func trashedRecord(
        in history: HistoryStore,
        original: String = "/Users/t/Library/Caches/app/file.bin",
        trash: String? = "/Users/t/.Trash/file.bin"
    ) throws -> OperationRecord {
        try history.record(
            OperationRecord(
                performedAt: .now,
                path: original,
                displayName: "file.bin",
                byteCount: 100,
                scannerID: "test",
                mode: .trash,
                outcome: .trashed,
                restorePath: trash
            )
        )
    }

    @Test("A trashed item is moved back to its original path and marked restored")
    func restoreMovesItemBack() throws {
        let history = try HistoryStore()
        let recorder = Recorder()
        let record = try trashedRecord(in: history)
        recorder.existing = ["/Users/t/.Trash/file.bin"]

        let subject = makeService(history: history, recorder: recorder)
        let destination = try subject.restore(recordID: #require(record.id))

        #expect(destination.path == "/Users/t/Library/Caches/app/file.bin")
        #expect(recorder.moves.count == 1)
        #expect(try history.restorable().isEmpty)
    }

    @Test("The parent folder is recreated when it was cleaned away too")
    func parentDirectoryIsRecreated() throws {
        let history = try HistoryStore()
        let recorder = Recorder()
        let record = try trashedRecord(in: history)
        recorder.existing = ["/Users/t/.Trash/file.bin"]

        let subject = makeService(history: history, recorder: recorder)
        try subject.restore(recordID: #require(record.id))

        #expect(recorder.createdDirectories.first?.path == "/Users/t/Library/Caches/app")
    }

    @Test("Restoring refuses to overwrite something already at the destination")
    func occupiedDestinationIsRefused() throws {
        let history = try HistoryStore()
        let recorder = Recorder()
        let record = try trashedRecord(in: history)
        recorder.existing = [
            "/Users/t/.Trash/file.bin",
            "/Users/t/Library/Caches/app/file.bin"
        ]

        let subject = makeService(history: history, recorder: recorder)

        #expect(throws: RestoreService.Failure.destinationOccupied("/Users/t/Library/Caches/app/file.bin")) {
            try subject.restore(recordID: #require(record.id))
        }
        #expect(recorder.moves.isEmpty)
        // Still offered, because nothing happened.
        #expect(try history.restorable().count == 1)
    }

    @Test("An item the user already emptied from the Trash reports that clearly")
    func missingFromTrashIsReported() throws {
        let history = try HistoryStore()
        let recorder = Recorder()
        let record = try trashedRecord(in: history)

        let subject = makeService(history: history, recorder: recorder)

        #expect(throws: RestoreService.Failure.missingFromTrash("/Users/t/.Trash/file.bin")) {
            try subject.restore(recordID: #require(record.id))
        }
    }

    @Test("A permanently deleted item cannot be restored")
    func permanentDeletionIsNotRestorable() throws {
        let history = try HistoryStore()
        let recorder = Recorder()
        let record = try history.record(
            OperationRecord(
                performedAt: .now,
                path: "/Users/t/Library/Caches/x",
                displayName: "x",
                byteCount: 1,
                scannerID: "test",
                mode: .permanent,
                outcome: .deleted
            )
        )

        let subject = makeService(history: history, recorder: recorder)

        #expect(throws: RestoreService.Failure.notRestorable) {
            try subject.restore(recordID: #require(record.id))
        }
    }

    @Test("Restoring twice is refused the second time")
    func doubleRestoreIsRefused() throws {
        let history = try HistoryStore()
        let recorder = Recorder()
        let record = try trashedRecord(in: history)
        recorder.existing = ["/Users/t/.Trash/file.bin"]
        let id = try #require(record.id)

        let subject = makeService(history: history, recorder: recorder)
        try subject.restore(recordID: id)

        #expect(throws: RestoreService.Failure.notRestorable) {
            try subject.restore(recordID: id)
        }
        #expect(recorder.moves.count == 1)
    }

    @Test("An unknown record id is reported rather than ignored")
    func unknownRecordIsReported() throws {
        let history = try HistoryStore()
        let subject = makeService(history: history, recorder: Recorder())

        #expect(throws: RestoreService.Failure.unknownRecord(999)) {
            try subject.restore(recordID: 999)
        }
    }

    @Test("A failed move leaves the record restorable so the user can retry")
    func failedMoveKeepsTheOffer() throws {
        let history = try HistoryStore()
        let recorder = Recorder()
        recorder.existing = ["/Users/t/.Trash/file.bin"]
        recorder.moveError = CocoaError(.fileWriteNoPermission)
        let record = try trashedRecord(in: history)

        let subject = makeService(history: history, recorder: recorder)

        #expect(throws: (any Error).self) { try subject.restore(recordID: #require(record.id)) }
        #expect(try history.restorable().count == 1)
    }

    @Test("Restorable records come from the history log")
    func restorableRecordsAreListed() throws {
        let history = try HistoryStore()
        _ = try trashedRecord(in: history)
        _ = try trashedRecord(in: history, original: "/Users/t/Library/Caches/b", trash: nil)

        let subject = makeService(history: history, recorder: Recorder())
        #expect(try subject.restorableRecords().count == 1)
    }
}
