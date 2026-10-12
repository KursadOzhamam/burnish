import Foundation
import CoreKit
import CoreKitMac
import ScanEngine
import SafetyKitMac

/// Runs one `CleanupRule`.
///
/// Reports only; nothing here deletes. Everything it finds goes to `DeletionService`, which
/// validates each path again before acting (CLAUDE.md §4).
public struct CleanupScanner: Scanning {
    public let rule: CleanupRule
    private let home: URL
    private let walker = FileTreeWalker()
    private let inspector: any RunningApplicationInspecting

    public init(
        rule: CleanupRule,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        inspector: any RunningApplicationInspecting = RunningApplicationInspector()
    ) {
        self.rule = rule
        self.home = home
        self.inspector = inspector
    }

    public var id: ScannerID { rule.id }
    public var weight: ScannerWeight { rule.weight }
    public var requiresFullDiskAccess: Bool { rule.requiresFullDiskAccess }

    public var title: LocalizedStringResource {
        CleanupStrings.key(rule.titleKey)
    }

    public var explanation: LocalizedStringResource {
        CleanupStrings.key(rule.explanationKey)
    }

    /// The roots this scanner may act within — its allowlist in `SafetyKit` (§4.2).
    public var allowedRoots: [URL] {
        rule.roots.map { $0.url(home: home) }
    }

    /// What a scan found, and what it could not look at.
    public struct Outcome: Sendable {
        public let items: [ScanItem]
        /// Roots that exist but could not be listed, typically for want of Full Disk Access.
        public let unreadableRoots: [URL]

        public init(items: [ScanItem], unreadableRoots: [URL] = []) {
            self.items = items
            self.unreadableRoots = unreadableRoots
        }
    }

    public func scan(progress: @Sendable (ScanProgress) -> Void) async throws -> [ScanItem] {
        let outcome = try await scanDetailed(progress: progress)
        // Nothing found *and* something unreadable is not "nothing to clean": say so.
        if outcome.items.isEmpty, !outcome.unreadableRoots.isEmpty {
            throw ScanError.fullDiskAccessRequired
        }
        return outcome.items
    }

    /// Like `scan`, but reports unreadable roots instead of folding them into an empty result.
    public func scanDetailed(progress: @Sendable (ScanProgress) -> Void) async throws -> Outcome {
        var items: [ScanItem] = []
        var unreadable: [URL] = []
        var discovered = ByteCount.zero

        // A browser that is open keeps its cache mapped; skip the whole scanner rather than
        // racing it (§4.5, §6.3).
        let runningOwners = Set(
            rule.ownerBundlePrefixes.filter { prefix in
                inspector.runningBundleIdentifiers().contains { $0.hasPrefix(prefix) }
            }
        )

        let roots = rule.roots
        for (index, root) in roots.enumerated() {
            try Task.checkCancellation()

            let url = root.url(home: home)
            guard walker.exists(url) else { continue }

            let fraction = Double(index + 1) / Double(roots.count)

            // Ownership is a property of the root, not of the files inside it: Safari's cache
            // root is named for its bundle identifier, while its children are named
            // "WebKitCache" and the like. Deciding per child silently failed to block anything.
            let blocked = blockedReason(forRoot: url, runningOwners: runningOwners)

            if root.listsChildren {
                do {
                    items += try scanChildren(
                        of: url,
                        blocked: blocked,
                        discovered: &discovered,
                        fraction: fraction,
                        progress: progress
                    )
                } catch FileTreeWalker.Failure.unreadable(let failed) {
                    unreadable.append(failed)
                }
            } else if let item = try scanWhole(
                url,
                blocked: blocked,
                discovered: &discovered,
                fraction: fraction,
                progress: progress
            ) {
                items.append(item)
            }
        }

        return Outcome(items: items, unreadableRoots: unreadable)
    }

    private func scanChildren(
        of url: URL,
        blocked: ScanItem.BlockedReason?,
        discovered: inout ByteCount,
        fraction: Double,
        progress: @Sendable (ScanProgress) -> Void
    ) throws -> [ScanItem] {
        var items: [ScanItem] = []

        let entries = try walker.measureChildren(of: url, isCancelled: { Task.isCancelled })
        for entry in entries {
            try Task.checkCancellation()

            let name = entry.url.lastPathComponent
            // The exclusion list is absolute: an excluded child is not offered at all, rather
            // than offered-but-unselected, so it cannot be swept up by "select all".
            guard !rule.excludedChildNames.contains(name) else { continue }
            guard entry.size.bytes > 0 else { continue }

            discovered += entry.size
            progress(
                ScanProgress(
                    fraction: fraction,
                    currentPath: entry.url.path,
                    discovered: discovered,
                    itemCount: items.count + 1
                )
            )

            items.append(
                ScanItem(
                    scanner: rule.id,
                    url: entry.url,
                    size: entry.size,
                    confidence: rule.confidence,
                    blockedReason: blocked
                )
            )
        }

        return items
    }

    private func scanWhole(
        _ url: URL,
        blocked: ScanItem.BlockedReason?,
        discovered: inout ByteCount,
        fraction: Double,
        progress: @Sendable (ScanProgress) -> Void
    ) throws -> ScanItem? {
        let result = try walker.measure(url, isCancelled: { Task.isCancelled })
        guard result.totalSize.bytes > 0 else { return nil }

        discovered += result.totalSize
        progress(
            ScanProgress(
                fraction: fraction,
                currentPath: url.path,
                discovered: discovered,
                itemCount: 1
            )
        )

        return ScanItem(
            scanner: rule.id,
            url: url,
            size: result.totalSize,
            confidence: rule.confidence,
            blockedReason: blocked
        )
    }

    /// Why nothing under this root can be acted on yet, if anything blocks it.
    ///
    /// Checked against the root's own path components, because that is where the owning
    /// application's bundle identifier appears.
    private func blockedReason(
        forRoot url: URL,
        runningOwners: Set<String>
    ) -> ScanItem.BlockedReason? {
        if rule.requiresHelper { return .needsHelper }

        let components = url.pathComponents
        let isOwnedByRunningApp = runningOwners.contains { owner in
            components.contains { component in
                component == owner || component.hasPrefix(owner)
            }
        }
        return isOwnedByRunningApp ? .ownerRunning : nil
    }
}

extension CleanupScanner {
    /// Every scanner in the catalogue, in catalogue order.
    public static func all(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        inspector: any RunningApplicationInspecting = RunningApplicationInspector()
    ) -> [CleanupScanner] {
        CleanupCatalogue.all.map { CleanupScanner(rule: $0, home: home, inspector: inspector) }
    }
}
