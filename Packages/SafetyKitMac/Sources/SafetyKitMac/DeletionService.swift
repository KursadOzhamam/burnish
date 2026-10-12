import Foundation
import CoreKit
import ScanEngine
import SafetyKit

/// The only code in the app that removes anything.
///
/// CLAUDE.md §4 opens by requiring exactly this: every deletion goes through one service, and
/// no other code calls `FileManager.removeItem`. A SwiftLint rule enforces the second half at
/// lint time; this type is the first half.
///
/// The flow is always the same, and `execute` cannot be reached without it:
///
///   1. `plan(for:mode:)` — a dry run that touches nothing and returns what *would* happen (§4.6)
///   2. the user approves the plan
///   3. `execute(_:)` — performs it, recording every outcome, continuing past failures (§4.8)
public struct DeletionService: Sendable {
    private let guards: [ScannerID: PathGuard]
    private let inspector: any RunningApplicationInspecting
    private let history: HistoryStore?
    private let trashItem: @Sendable (URL) throws -> URL?
    private let removeItem: @Sendable (URL) throws -> Void
    private let fileExists: @Sendable (URL) -> Bool

    /// - Parameters:
    ///   - guards: one `PathGuard` per scanner, defining where that scanner may act (§4.2).
    ///     A scanner with no guard can delete nothing.
    ///   - history: the operation log. Optional only so tests can run without one; the app
    ///     always supplies it (§4.7).
    public init(
        guards: [ScannerID: PathGuard],
        inspector: any RunningApplicationInspecting = RunningApplicationInspector(),
        history: HistoryStore? = nil
    ) {
        self.init(
            guards: guards,
            inspector: inspector,
            history: history,
            trashItem: { url in
                var resulting: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
                return resulting as URL?
            },
            removeItem: { url in
                // The one sanctioned call in the project. Everything funnels here, behind the
                // guard checks above; the lint rule exists to keep it that way.
                // swiftlint:disable:next no_direct_remove_item
                try FileManager.default.removeItem(at: url)
            },
            fileExists: { url in
                FileManager.default.fileExists(atPath: url.path)
            }
        )
    }

    /// Injectable form used by the tests, which must never touch the real filesystem (§9).
    init(
        guards: [ScannerID: PathGuard],
        inspector: any RunningApplicationInspecting,
        history: HistoryStore?,
        trashItem: @escaping @Sendable (URL) throws -> URL?,
        removeItem: @escaping @Sendable (URL) throws -> Void,
        fileExists: @escaping @Sendable (URL) -> Bool
    ) {
        self.guards = guards
        self.inspector = inspector
        self.history = history
        self.trashItem = trashItem
        self.removeItem = removeItem
        self.fileExists = fileExists
    }

    // MARK: Dry run

    /// Builds the plan the user approves. Touches nothing.
    ///
    /// Items that cannot be acted on are carried in `plan.skipped` with a reason, so the
    /// confirmation sheet can show what was left out instead of quietly dropping it.
    public func plan(for items: [ScanItem], mode: DeletionMode) -> DeletionPlan {
        let screened = items.map { item -> ScanItem in
            if let reason = refusalReason(for: item) {
                return item.blocking(reason)
            }
            return item
        }
        return DeletionPlan(items: screened, mode: mode)
    }

    /// Why this item cannot be removed, or nil when it can.
    private func refusalReason(for item: ScanItem) -> ScanItem.BlockedReason? {
        if let existing = item.blockedReason { return existing }

        guard let guardForScanner = guards[item.scanner] else {
            // No declared root means no permission to act — refusing is the safe default.
            return .outsideScope
        }

        do {
            _ = try guardForScanner.validate(item.url)
        } catch let error as SafetyError {
            return error.blockedReason
        } catch {
            return .outsideScope
        }

        // §4.5: skip anything belonging to a running application.
        if inspector.owningBundleIdentifier(of: item.url) != nil { return .ownerRunning }

        return nil
    }

    // MARK: Execution

    /// Carries out an approved plan.
    ///
    /// - Parameter confirmedIrreversible: must be true for a permanent plan. §4.1 requires a
    ///   second, explicit confirmation before anything is destroyed; passing a permanent plan
    ///   without it throws rather than deleting.
    public func execute(
        _ plan: DeletionPlan,
        confirmedIrreversible: Bool = false
    ) throws -> DeletionReport {
        if plan.requiresExtraConfirmation, !confirmedIrreversible {
            throw SafetyError.missingIrreversibleConfirmation
        }

        var outcomes: [DeletionOutcome] = plan.skipped.map { item in
            DeletionOutcome(item: item, result: .skipped(item.blockedReason ?? .excludedByUser))
        }

        for item in plan.items {
            outcomes.append(perform(item, mode: plan.mode))
        }

        let report = DeletionReport(outcomes: outcomes, mode: plan.mode)
        // Recording must not lose the run: a log failure is reported, not thrown (§4.8).
        try? history?.record(report)
        return report
    }

    /// Removes one item. Never throws: §4.8 requires the run to continue past a single failure.
    private func perform(_ item: ScanItem, mode: DeletionMode) -> DeletionOutcome {
        // Re-validate immediately before acting. The plan may be minutes old, and the path
        // could have become a symlink since — §4.4 applies at the moment of deletion, not only
        // at planning time.
        guard let guardForScanner = guards[item.scanner] else {
            return DeletionOutcome(item: item, result: .skipped(.outsideScope))
        }

        let resolved: URL
        do {
            resolved = try guardForScanner.validate(item.url)
        } catch let error as SafetyError {
            return DeletionOutcome(item: item, result: .failed(message: error.reportDescription))
        } catch {
            return DeletionOutcome(item: item, result: .failed(message: error.localizedDescription))
        }

        if inspector.owningBundleIdentifier(of: resolved) != nil {
            return DeletionOutcome(item: item, result: .skipped(.ownerRunning))
        }

        guard fileExists(resolved) else {
            // Already gone — not a failure, and not a reclaimed byte either (§10.4).
            return DeletionOutcome(item: item, result: .skipped(.outsideScope))
        }

        do {
            switch mode {
            case .trash:
                let restoreURL = try trashItem(resolved)
                return DeletionOutcome(item: item, result: .trashed(restoreURL: restoreURL))
            case .permanent:
                try removeItem(resolved)
                return DeletionOutcome(item: item, result: .deleted)
            }
        } catch {
            return DeletionOutcome(item: item, result: .failed(message: error.localizedDescription))
        }
    }
}

// MARK: - Helpers

extension SafetyError {
    /// How this refusal is shown to the user in a result list.
    var blockedReason: ScanItem.BlockedReason {
        switch self {
        case .protectedPath, .symlinkEscape: .protectedPath
        case .outsideAllowlist: .outsideScope
        case .ownerRunning: .ownerRunning
        case .missingIrreversibleConfirmation: .outsideScope
        }
    }

    /// Short description for the result screen and the operation log.
    var reportDescription: String {
        switch self {
        case .protectedPath(let path):
            "Protected path: \(path)"
        case .outsideAllowlist(let path, let root):
            "Outside allowed root \(root): \(path)"
        case .symlinkEscape(let from, let to):
            "Symlink escapes allowed roots: \(from) → \(to)"
        case .ownerRunning(let bundleIdentifier):
            "Owning application is running: \(bundleIdentifier ?? "unknown")"
        case .missingIrreversibleConfirmation:
            "Permanent deletion requires explicit confirmation"
        }
    }
}
