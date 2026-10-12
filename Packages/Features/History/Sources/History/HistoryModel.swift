import Foundation
import Observation
import CoreKit
import SafetyKit
import SafetyKitMac

/// Anything that can put a trashed item back. A protocol so the model can be tested without
/// touching the filesystem (CLAUDE.md §9).
public protocol RestoringItems: Sendable {
    func restore(recordID: Int64) throws -> URL
}

extension RestoreService: RestoringItems {
    public func restore(recordID: Int64) throws -> URL {
        try self.restore(recordID: recordID) as URL
    }
}

/// State behind the history screen — CLAUDE.md §4.7 and §6.9.
@Observable
@MainActor
public final class HistoryModel {

    /// The outcome of the last restore attempt, shown to the user.
    public enum Notice: Equatable, Sendable {
        case restored(name: String)
        case failed(RestoreService.Failure)
    }

    public private(set) var records: [OperationRecord] = []
    public private(set) var totalReclaimed: ByteCount = .zero
    public private(set) var notice: Notice?

    /// False when the log could not be opened, so the screen can say so rather than look empty.
    public let isAvailable: Bool

    private let store: HistoryStore?
    private let restorer: (any RestoringItems)?

    public init(store: HistoryStore?, restorer: (any RestoringItems)? = nil) {
        self.store = store
        self.restorer = restorer ?? store.map { RestoreService(history: $0) }
        self.isAvailable = store != nil
    }

    public func reload() {
        guard let store else { return }
        records = (try? store.recent()) ?? []
        totalReclaimed = (try? store.totalReclaimed()) ?? .zero
    }

    /// Restores one item and reports exactly what happened.
    public func restore(_ record: OperationRecord) {
        guard let id = record.id, let restorer else { return }

        do {
            let destination = try restorer.restore(recordID: id)
            notice = .restored(name: destination.lastPathComponent)
        } catch let failure as RestoreService.Failure {
            notice = .failed(failure)
        } catch {
            notice = .failed(.moveFailed(error.localizedDescription))
        }
        reload()
    }

    public func dismissNotice() {
        notice = nil
    }

    /// Items that can still be put back.
    public var restorableCount: Int {
        records.filter(\.canRestore).count
    }
}
