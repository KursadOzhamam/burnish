import Foundation
import CoreKit
import CoreKitMac
import ScanEngine
import SafetyKitMac

/// Finds the largest files under the folders the user chose (CLAUDE.md §6.7).
///
/// Reports only. Everything it finds is the user's own content, so every item is low confidence
/// (never preselected) and removal goes through `DeletionService` to the Trash.
public struct LargeFilesScanner: HeavyScanning {
    public let id = ScannerID("files.large")
    public let title: LocalizedStringResource = "files.large.title"

    public let roots: [URL]
    public let minimumSize: ByteCount
    /// Upper bound on the list, so a Mac full of big files does not produce a 50,000 row screen.
    public let limit: Int

    private let clock: @Sendable () -> Date

    public init(
        roots: [URL],
        minimumSize: ByteCount = ByteCount(100 * 1_024 * 1_024),
        limit: Int = 500,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.roots = roots
        self.minimumSize = minimumSize
        self.limit = limit
        self.clock = clock
    }

    /// Folders worth searching by default: the user's own, never `Library` or dot folders.
    public static func defaultRoots(home: URL) -> [URL] {
        let fileManager = FileManager()
        let children = (try? fileManager.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return children
            .filter { url in
                let name = url.lastPathComponent
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                return isDirectory && name != "Library" && name != "Applications" && name != "Public"
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public func scan(
        progress: @Sendable (ScanProgress) -> Void,
        partial: @Sendable ([ScanItem]) -> Void
    ) async throws -> [ScanItem] {
        try walk(progress: progress, partial: partial)
    }

    /// Synchronous because `FileManager.DirectoryEnumerator` cannot be iterated from an async
    /// context. Cancellation is still honoured through `Task.checkCancellation()`.
    private func walk(
        progress: @Sendable (ScanProgress) -> Void,
        partial: @Sendable ([ScanItem]) -> Void
    ) throws -> [ScanItem] {
        var found: [ScanItem] = []
        var seenIdentifiers = Set<AnyHashable>()
        var visited = 0
        var lastReported = 0

        let keys: [URLResourceKey] = [
            .totalFileAllocatedSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey,
            .fileResourceIdentifierKey, .contentModificationDateKey, .contentAccessDateKey
        ]

        for (index, root) in roots.enumerated() {
            try Task.checkCancellation()
            guard let enumerator = FileManager().enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                visited += 1
                if visited % 256 == 0 {
                    try Task.checkCancellation()
                    progress(
                        ScanProgress(
                            fraction: Double(index) / Double(max(1, roots.count)),
                            currentPath: url.path,
                            discovered: found.map(\.size).reduce(.zero, +),
                            itemCount: found.count
                        )
                    )
                }

                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                // Symlinks are not followed (§4.4); packages (.app, .photoslibrary) are not
                // entered and are not treated as files.
                if values.isSymbolicLink == true { continue }
                if values.isPackage == true { continue }
                guard values.isRegularFile == true else { continue }

                let size = ByteCount(Int64(values.totalFileAllocatedSize ?? 0))
                guard size >= minimumSize else { continue }

                // A hard link is one file on disk: count it once.
                if let identifier = values.fileResourceIdentifier as? AnyHashable,
                   !seenIdentifiers.insert(identifier).inserted {
                    continue
                }

                let lastUsed = [values.contentAccessDate, values.contentModificationDate]
                    .compactMap { $0 }.max()
                found.append(
                    ScanItem(
                        scanner: id, url: url, size: size, confidence: .low, lastUsed: lastUsed
                    )
                )
                found.sort { $0.size > $1.size }
                if found.count > limit { found.removeLast() }

                // Partial results: everything found so far, biggest first.
                if found.count - lastReported >= 10 {
                    lastReported = found.count
                    partial(found)
                }
            }
        }

        progress(ScanProgress(fraction: 1, discovered: found.map(\.size).reduce(.zero, +), itemCount: found.count))
        partial(found)
        return found
    }
}

extension Sequence where Element == ScanItem {
    /// Items untouched for at least `days` days, as of `now`. Items with no known date are
    /// kept out: not knowing is not evidence that a file is old.
    public func untouched(forAtLeast days: Int, now: Date) -> [ScanItem] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return filter { ($0.lastUsed ?? .distantFuture) < cutoff }
    }
}
