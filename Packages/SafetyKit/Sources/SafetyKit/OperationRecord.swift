import Foundation
import CoreKit
import GRDB

/// One row of the operation history.
///
/// CLAUDE.md §4.7: every deletion is written with its time, path, size and kind, is visible on
/// the history screen, and — when it went to the Trash — can be put back.
public struct OperationRecord: Sendable, Hashable, Identifiable, Codable {
    /// Database row id, assigned on insert.
    public var id: Int64?

    public var performedAt: Date

    /// Where the item was.
    public var path: String

    /// Name as it was shown to the user.
    public var displayName: String

    /// Size at the time of the operation.
    public var byteCount: Int64

    /// Which scanner proposed it, for filtering the history by area.
    public var scannerID: String

    public var mode: DeletionMode

    public var outcome: Outcome

    /// Where the item now sits in the Trash, when it can be restored.
    public var restorePath: String?

    /// Failure detail, shown on the result screen (§4.8).
    public var failureMessage: String?

    /// Set once the user has put the item back, so it is not offered twice.
    public var restoredAt: Date?

    /// Which platform performed it — present from the start so a later iOS companion can share
    /// the same history schema (CLAUDE.md §12.3).
    public var platform: String

    public enum Outcome: String, Sendable, Codable, CaseIterable {
        case trashed
        case deleted
        case skipped
        case failed
    }

    public init(
        id: Int64? = nil,
        performedAt: Date,
        path: String,
        displayName: String,
        byteCount: Int64,
        scannerID: String,
        mode: DeletionMode,
        outcome: Outcome,
        restorePath: String? = nil,
        failureMessage: String? = nil,
        restoredAt: Date? = nil,
        platform: String = OperationRecord.currentPlatform
    ) {
        self.id = id
        self.performedAt = performedAt
        self.path = path
        self.displayName = displayName
        self.byteCount = byteCount
        self.scannerID = scannerID
        self.mode = mode
        self.outcome = outcome
        self.restorePath = restorePath
        self.failureMessage = failureMessage
        self.restoredAt = restoredAt
        self.platform = platform
    }

    public static var currentPlatform: String {
        #if os(macOS)
        "macOS"
        #elseif os(iOS)
        "iOS"
        #else
        "unknown"
        #endif
    }

    public var size: ByteCount { ByteCount(byteCount) }

    /// Whether the history screen should offer to put this back.
    ///
    /// Only trashed items with a known location, and only once.
    public var canRestore: Bool {
        outcome == .trashed && restorePath != nil && restoredAt == nil
    }
}

// MARK: - Persistence

extension OperationRecord: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "operation"

    public enum Columns {
        public static let id = Column("id")
        public static let performedAt = Column("performedAt")
        public static let path = Column("path")
        public static let outcome = Column("outcome")
        public static let restoredAt = Column("restoredAt")
        public static let scannerID = Column("scannerID")
        public static let restorePath = Column("restorePath")
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
