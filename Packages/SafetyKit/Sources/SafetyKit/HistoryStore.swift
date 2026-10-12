import Foundation
import CoreKit
import ScanEngine
import GRDB

/// The operation log required by CLAUDE.md §4.7.
///
/// An append-only record of everything the app removed, backing the history screen and the
/// restore flow. Writing here is part of deleting, not an optional extra: `DeletionService`
/// records every outcome, including failures and skips, so the result screen can explain what
/// happened (§4.8).
public final class HistoryStore: Sendable {
    private let database: DatabaseQueue

    /// Opens (or creates) the log at `url`.
    public init(url: URL) throws {
        var configuration = Configuration()
        // The log is small and written in bursts after a cleanup; WAL keeps the UI responsive
        // while a run is still being recorded.
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        self.database = try DatabaseQueue(path: url.path, configuration: configuration)
        try Self.migrator.migrate(database)
    }

    /// In-memory store for tests and previews.
    public init() throws {
        self.database = try DatabaseQueue()
        try Self.migrator.migrate(database)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_operations") { db in
            try db.create(table: OperationRecord.databaseTableName) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("performedAt", .datetime).notNull().indexed()
                table.column("path", .text).notNull()
                table.column("displayName", .text).notNull()
                table.column("byteCount", .integer).notNull()
                table.column("scannerID", .text).notNull().indexed()
                table.column("mode", .text).notNull()
                table.column("outcome", .text).notNull().indexed()
                table.column("restorePath", .text)
                table.column("failureMessage", .text)
                table.column("restoredAt", .datetime)
                table.column("platform", .text).notNull()
            }
        }

        return migrator
    }

    // MARK: Writing

    /// Records every outcome of a run, including skips and failures.
    @discardableResult
    public func record(_ report: DeletionReport) throws -> [OperationRecord] {
        let records = report.outcomes.map { Self.makeRecord(from: $0, mode: report.mode) }
        return try database.write { db in
            try records.map { record in
                var copy = record
                try copy.insert(db)
                return copy
            }
        }
    }

    @discardableResult
    public func record(_ record: OperationRecord) throws -> OperationRecord {
        var copy = record
        try database.write { db in try copy.insert(db) }
        return copy
    }

    /// Marks an item as restored so the history screen stops offering it.
    public func markRestored(id: Int64, at date: Date = .now) throws {
        try database.write { db in
            try db.execute(
                sql: "UPDATE operation SET restoredAt = ? WHERE id = ?",
                arguments: [date, id]
            )
        }
    }

    // MARK: Reading

    /// Most recent operations first.
    public func recent(limit: Int = 200) throws -> [OperationRecord] {
        try database.read { db in
            try OperationRecord
                .order(OperationRecord.Columns.performedAt.desc, OperationRecord.Columns.id.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Items the user can still put back.
    public func restorable() throws -> [OperationRecord] {
        try database.read { db in
            try OperationRecord
                .filter(OperationRecord.Columns.outcome == OperationRecord.Outcome.trashed.rawValue)
                .filter(OperationRecord.Columns.restoredAt == nil)
                .filter(OperationRecord.Columns.restorePath != nil)
                .order(OperationRecord.Columns.performedAt.desc)
                .fetchAll(db)
        }
    }

    public func operations(scannerID: ScannerID, limit: Int = 200) throws -> [OperationRecord] {
        try database.read { db in
            try OperationRecord
                .filter(OperationRecord.Columns.scannerID == scannerID.rawValue)
                .order(OperationRecord.Columns.performedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func record(id: Int64) throws -> OperationRecord? {
        try database.read { db in try OperationRecord.fetchOne(db, key: id) }
    }

    public func count() throws -> Int {
        try database.read { db in try OperationRecord.fetchCount(db) }
    }

    /// Total space reclaimed across the whole log.
    ///
    /// Counts only items that were really removed — §10.4 forbids inflating this.
    public func totalReclaimed() throws -> ByteCount {
        try database.read { db in
            let sum = try Int64.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(SUM(byteCount), 0) FROM operation
                    WHERE outcome IN (?, ?)
                    """,
                arguments: [
                    OperationRecord.Outcome.trashed.rawValue,
                    OperationRecord.Outcome.deleted.rawValue
                ]
            ) ?? 0
            return ByteCount(sum)
        }
    }

    /// Removes entries older than `date`. The user controls retention; nothing expires on its own.
    @discardableResult
    public func prune(before date: Date) throws -> Int {
        try database.write { db in
            try OperationRecord
                .filter(OperationRecord.Columns.performedAt < date)
                .deleteAll(db)
        }
    }

    // MARK: Mapping

    private static func makeRecord(from outcome: DeletionOutcome, mode: DeletionMode) -> OperationRecord {
        let mapped: (OperationRecord.Outcome, String?, String?) = switch outcome.result {
        case .trashed(let restoreURL): (.trashed, restoreURL?.path, nil)
        case .deleted: (.deleted, nil, nil)
        case .skipped(let reason): (.skipped, nil, reason.rawValue)
        case .failed(let message): (.failed, nil, message)
        }

        return OperationRecord(
            performedAt: outcome.completedAt,
            path: outcome.item.url.path,
            displayName: outcome.item.displayName,
            byteCount: outcome.item.totalSize.bytes,
            scannerID: outcome.item.scanner.rawValue,
            mode: mode,
            outcome: mapped.0,
            restorePath: mapped.1,
            failureMessage: mapped.2
        )
    }
}
