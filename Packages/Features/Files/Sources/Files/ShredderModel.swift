import Foundation
import DeletionUI
import Observation
import CoreKit
import CoreKitMac
import ScanEngine
import SafetyKit
import SafetyKitMac

/// State behind the shredder (CLAUDE.md §6.7): permanent removal of files the user picks.
///
/// The only feature that destroys data, so it is the most guarded:
/// - it acts on exactly the files the user added and nothing else (each is a declared target);
/// - the protected-paths list still wins over the user's own pick;
/// - nothing runs until the user has ticked that this cannot be undone, and then approves a
///   sheet that says so again;
/// - it does not claim to overwrite: on an SSD with APFS (copy-on-write, wear levelling, TRIM)
///   overwriting does not guarantee the old data is gone, and saying otherwise would be false.
@Observable
@MainActor
public final class ShredderModel {
    public enum Phase: Sendable {
        case idle
        case deleting
        case finished(DeletionReport)
    }

    public private(set) var entries: [ScanItem] = []
    /// The user's statement that this is permanent. Required before a plan can be built.
    public var acknowledgedIrreversible = false
    public let canRecordHistory: Bool

    private let approval = ApprovalFlow()
    private let history: HistoryStore?
    private let walker = FileTreeWalker()
    private let scannerID = ScannerID("files.shredder")

    public var pendingPlan: DeletionPlan? { approval.pendingPlan }

    public init(history: HistoryStore? = nil) {
        self.history = history
        self.canRecordHistory = history != nil
    }

    public var phase: Phase {
        if let report = approval.report { return .finished(report) }
        if approval.isDeleting { return .deleting }
        return .idle
    }

    // MARK: Entries

    /// Adds files or folders the user picked. They are screened first, so a protected folder is
    /// refused at once instead of being walked for a size nobody will use; sizes of what is left
    /// are measured off the main thread.
    public func add(_ urls: [URL]) async {
        let known = Set(entries.map(\.url.path))
        let id = scannerID
        let fresh: [ScanItem] = urls.map(\.standardizedFileURL)
            .filter { !known.contains($0.path) && FileManager().fileExists(atPath: $0.path) }
            .map { ScanItem(scanner: id, url: $0, size: .zero, confidence: .low) }
        guard !fresh.isEmpty else { return }

        entries = approval.screened(rebuildGuard(adding: fresh))

        let toMeasure = entries.filter { $0.isActionable && $0.size == .zero }
        let sizes: [UUID: ByteCount] = await Task.detached { [walker = self.walker] in
            var result: [UUID: ByteCount] = [:]
            for item in toMeasure {
                var isDirectory: ObjCBool = false
                _ = FileManager().fileExists(atPath: item.url.path, isDirectory: &isDirectory)
                if isDirectory.boolValue {
                    result[item.id] = (try? walker.measure(item.url).totalSize) ?? .zero
                } else {
                    let bytes = (try? item.url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?
                        .totalFileAllocatedSize ?? 0
                    result[item.id] = ByteCount(Int64(bytes))
                }
            }
            return result
        }.value

        entries = entries.map { item in
            guard let size = sizes[item.id] else { return item }
            return ScanItem(
                id: item.id, scanner: item.scanner, url: item.url, displayName: item.displayName,
                size: size, confidence: item.confidence, blockedReason: item.blockedReason, lastUsed: item.lastUsed
            )
        }
    }

    public func remove(_ item: ScanItem) {
        entries.removeAll { $0.id == item.id }
        entries = approval.screened(rebuildGuard(adding: []))
    }

    public func clear() {
        entries = []
        acknowledgedIrreversible = false
        approval.reset()
    }

    /// Every chosen path is a declared target, so exactly those can be removed and no neighbour.
    /// The service is rebuilt whenever the list changes. Returns the entries with earlier
    /// refusals cleared, ready to be screened again.
    private func rebuildGuard(adding added: [ScanItem]) -> [ScanItem] {
        let all = entries.map(unblocked) + added
        let targets = all.map(\.url)
        approval.use(
            DeletionService(
                guards: [scannerID: PathGuard(allowedRoots: [], allowedTargets: targets)],
                history: history
            )
        )
        return all
    }

    private func unblocked(_ item: ScanItem) -> ScanItem {
        ScanItem(
            id: item.id, scanner: item.scanner, url: item.url, displayName: item.displayName,
            size: item.size, confidence: item.confidence, lastUsed: item.lastUsed
        )
    }

    public var actionable: [ScanItem] { entries.filter(\.isActionable) }
    public var blocked: [ScanItem] { entries.filter { !$0.isActionable } }
    public var totalSize: ByteCount { actionable.totalSize() }

    // MARK: Approval

    public var canPrepare: Bool { acknowledgedIrreversible && !actionable.isEmpty }

    /// Builds the permanent plan and opens the sheet. Refused until the user has acknowledged
    /// that it cannot be undone. Touches nothing.
    public func prepareConfirmation() {
        guard canPrepare else { return }
        approval.prepare(actionable, mode: .permanent)
    }

    public func dismissConfirmation() { approval.dismiss() }

    public func confirm(_ plan: DeletionPlan) {
        approval.confirm(plan) { [weak self] in
            self?.entries = []
            self?.acknowledgedIrreversible = false
        }
    }

    public func reset() {
        entries = []
        acknowledgedIrreversible = false
        approval.reset()
    }
}
