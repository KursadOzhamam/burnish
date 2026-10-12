import Foundation
import SafetyKit

/// Puts a trashed item back where it came from.
///
/// CLAUDE.md §4.7: items moved to the Trash can be restored from the history screen. Restoring
/// is deliberately conservative — it refuses rather than overwrites, and it only ever moves a
/// file out of the Trash, never out of anywhere else.
public struct RestoreService: Sendable {
    private let history: HistoryStore
    private let moveItem: @Sendable (URL, URL) throws -> Void
    private let fileExists: @Sendable (URL) -> Bool
    private let createDirectory: @Sendable (URL) throws -> Void

    public init(history: HistoryStore) {
        self.init(
            history: history,
            moveItem: { from, to in try FileManager.default.moveItem(at: from, to: to) },
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            createDirectory: { url in
                try FileManager.default.createDirectory(
                    at: url,
                    withIntermediateDirectories: true
                )
            }
        )
    }

    init(
        history: HistoryStore,
        moveItem: @escaping @Sendable (URL, URL) throws -> Void,
        fileExists: @escaping @Sendable (URL) -> Bool,
        createDirectory: @escaping @Sendable (URL) throws -> Void
    ) {
        self.history = history
        self.moveItem = moveItem
        self.fileExists = fileExists
        self.createDirectory = createDirectory
    }

    /// Why a restore could not happen.
    public enum Failure: Error, Sendable, Equatable {
        /// No such entry in the log.
        case unknownRecord(Int64)
        /// Permanently deleted, already restored, or never trashed.
        case notRestorable
        /// The item is no longer in the Trash — the user likely emptied it.
        case missingFromTrash(String)
        /// Something already occupies the original path. Refusing beats overwriting.
        case destinationOccupied(String)
        /// The move itself failed.
        case moveFailed(String)
    }

    /// Restores the item recorded under `id` to its original location.
    @discardableResult
    public func restore(recordID: Int64) throws -> URL {
        guard let record = try history.record(id: recordID) else {
            throw Failure.unknownRecord(recordID)
        }
        guard record.canRestore, let trashPath = record.restorePath else {
            throw Failure.notRestorable
        }

        let source = URL(fileURLWithPath: trashPath)
        let destination = URL(fileURLWithPath: record.path)

        guard fileExists(source) else {
            throw Failure.missingFromTrash(trashPath)
        }
        // Never clobber whatever is there now: the user may have recreated the file, and
        // silently replacing it would be a second data loss caused by an undo.
        guard !fileExists(destination) else {
            throw Failure.destinationOccupied(destination.path)
        }

        do {
            // The original folder may itself have been cleaned away since.
            try createDirectory(destination.deletingLastPathComponent())
            try moveItem(source, destination)
        } catch {
            throw Failure.moveFailed(error.localizedDescription)
        }

        try history.markRestored(id: recordID)
        return destination
    }

    /// Everything the history screen can currently offer to put back.
    public func restorableRecords() throws -> [OperationRecord] {
        try history.restorable()
    }
}
