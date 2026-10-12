import Foundation
import CoreKit
import ScanEngine

/// Measures a folder tree for the Space Lens map (CLAUDE.md §6.7).
///
/// Returns one root `ScanItem` whose `children` mirror the folder structure. In that tree a
/// directory's own `size` is zero and its weight is the sum of what is under it, so
/// `totalSize` is the figure to draw.
///
/// Reports only. Hidden files are included: they are real space. Symlinks are never followed and
/// a hard link is counted once (§4.4, §6.7). Packages (.app, .photoslibrary) are measured as one
/// block and not opened, so the map shows "Photos Library" rather than its internals.
public struct SpaceLensScanner: HeavyScanning {
    public let id = ScannerID("files.spaceLens")
    public let title: LocalizedStringResource = "files.spaceLens.title"

    public let root: URL
    /// Largest children kept per folder; the rest are folded into one "other" block so a folder
    /// with 200,000 entries does not become 200,000 nodes in memory.
    public let childLimit: Int
    /// Anything smaller than this is folded into its parent's "other" block. A block that small
    /// is invisible on a map anyway, and keeping all of them cost half a million nodes on a
    /// real home folder.
    public let minimumNodeSize: ByteCount

    public init(root: URL, childLimit: Int = 120, minimumNodeSize: ByteCount = ByteCount(1_048_576)) {
        self.root = root
        self.childLimit = childLimit
        self.minimumNodeSize = minimumNodeSize
    }

    public func scan(
        progress: @Sendable (ScanProgress) -> Void,
        partial: @Sendable ([ScanItem]) -> Void
    ) async throws -> [ScanItem] {
        let settings = Settings(childLimit: childLimit, minimumNodeSize: minimumNodeSize)
        let state = State()
        let id = self.id
        let top = try Self.children(of: root)

        // The first two levels are measured side by side: that is where a home folder splits
        // into a few huge branches (Library, Desktop), and one thread walking them in turn took
        // more than three minutes.
        let built = try await withoutActuallyEscaping(progress) { escapable in
            let report: @Sendable (String) -> Void = { path in
                let snapshot = state.snapshot()
                escapable(
                    ScanProgress(
                        fraction: nil, currentPath: path,
                        discovered: ByteCount(snapshot.total), itemCount: snapshot.visited
                    )
                )
            }
            state.report = report
            // The closure may not outlive this block, so the state must let go of it.
            defer { state.report = nil }
            return try await Self.measureChildren(
                top, id: id, state: state, settings: settings, depth: 0, report: report
            )
        }
        let result = Self.rootItem(root, id: id, children: built, settings: settings)
        progress(
            ScanProgress(fraction: 1, discovered: ByteCount(state.snapshot().total), itemCount: state.snapshot().visited)
        )
        return [result]
    }

    struct Settings: Sendable {
        let childLimit: Int
        let minimumNodeSize: ByteCount
    }

    // MARK: Measuring (synchronous: DirectoryEnumerator cannot be iterated from async code)

    private static let keys: [URLResourceKey] = [
        .totalFileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
        .fileResourceIdentifierKey, .contentModificationDateKey, .contentAccessDateKey
    ]

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var seen = Set<AnyHashable>()
        private var total: Int64 = 0
        private var visited = 0
        var report: (@Sendable (String) -> Void)?

        /// True the first time a file identity is seen, so a hard link is counted once.
        func claim(_ identifier: AnyHashable) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return seen.insert(identifier).inserted
        }

        func add(bytes: Int64) {
            lock.lock(); total += bytes; lock.unlock()
        }

        /// Called for every entry; asks for a progress report every 1,000th so the readout moves
        /// during a long walk through one huge folder, not only when a new branch starts.
        func visit(path: String, report: (@Sendable (String) -> Void)?) {
            lock.lock()
            visited += 1
            let due = visited % 1_000 == 0
            lock.unlock()
            if due { report?(path) }
        }

        func snapshot() -> (total: Int64, visited: Int) {
            lock.lock(); defer { lock.unlock() }
            return (total, visited)
        }
    }

    /// Measures sibling entries concurrently down to depth 2, then one thread per subtree.
    private static func measureChildren(
        _ entries: [URL], id: ScannerID, state: State, settings: Settings, depth: Int,
        report: @escaping @Sendable (String) -> Void
    ) async throws -> [ScanItem] {
        guard depth < 2 else {
            var nodes: [ScanItem] = []
            for entry in entries {
                if let child = try node(for: entry, id: id, state: state, settings: settings) { nodes.append(child) }
            }
            return nodes
        }
        return try await withThrowingTaskGroup(of: ScanItem?.self) { group in
            for entry in entries {
                group.addTask {
                    try Task.checkCancellation()
                    report(entry.path)
                    return try await asyncNode(
                        for: entry, id: id, state: state, settings: settings, depth: depth, report: report
                    )
                }
            }
            var nodes: [ScanItem] = []
            for try await child in group { if let child { nodes.append(child) } }
            return nodes
        }
    }

    private static func asyncNode(
        for url: URL, id: ScannerID, state: State, settings: Settings, depth: Int,
        report: @escaping @Sendable (String) -> Void
    ) async throws -> ScanItem? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)),
              values.isSymbolicLink != true,
              values.isDirectory == true, values.isPackage != true
        else {
            return try node(for: url, id: id, state: state, settings: settings)
        }
        state.visit(path: url.path, report: state.report)
        let lastUsed = [values.contentAccessDate, values.contentModificationDate].compactMap { $0 }.max()
        let entries: [URL]
        do {
            entries = try children(of: url)
        } catch {
            return ScanItem(
                scanner: id, url: url, size: .zero, confidence: .low,
                blockedReason: .needsFullDiskAccess, lastUsed: lastUsed
            )
        }
        let nodes = try await measureChildren(
            entries, id: id, state: state, settings: settings, depth: depth + 1, report: report
        )
        return ScanItem(
            scanner: id, url: url, size: .zero, confidence: .low,
            children: fold(nodes, in: url, id: id, settings: settings), lastUsed: lastUsed
        )
    }

    private static func rootItem(_ root: URL, id: ScannerID, children: [ScanItem], settings: Settings) -> ScanItem {
        ScanItem(
            scanner: id, url: root, size: .zero, confidence: .low,
            children: fold(children, in: root, id: id, settings: settings)
        )
    }

    private static func children(of directory: URL) throws -> [URL] {
        try FileManager().contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: []
        )
    }

    /// One node: a file, a package (measured whole) or a folder (recursed into).
    private static func node(for url: URL, id: ScannerID, state: State, settings: Settings) throws -> ScanItem? {
        // Foundation hands back autoreleased objects, and a worker thread of the async pool never
        // drains its own pool, so without this a walk over half a million files held on to
        // several hundred megabytes of resource values it had already finished with.
        try autoreleasepool {
            try measureNode(for: url, id: id, state: state, settings: settings)
        }
    }

    private static func measureNode(for url: URL, id: ScannerID, state: State, settings: Settings) throws -> ScanItem? {
        try Task.checkCancellation()
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        if values.isSymbolicLink == true { return nil }
        state.visit(path: url.path, report: state.report)
        let lastUsed = [values.contentAccessDate, values.contentModificationDate].compactMap { $0 }.max()

        if values.isDirectory == true, values.isPackage != true {
            let entries: [URL]
            do {
                entries = try children(of: url)
            } catch {
                // Exists but cannot be read: show it as a block we could not open, not as empty.
                return ScanItem(
                    scanner: id, url: url, size: .zero, confidence: .low,
                    blockedReason: .needsFullDiskAccess, lastUsed: lastUsed
                )
            }
            var nodes: [ScanItem] = []
            for entry in entries {
                if let child = try node(for: entry, id: id, state: state, settings: settings) {
                    nodes.append(child)
                }
            }
            return ScanItem(
                scanner: id, url: url, size: .zero, confidence: .low,
                children: fold(nodes, in: url, id: id, settings: settings), lastUsed: lastUsed
            )
        }

        let bytes: Int64
        if values.isDirectory == true {
            bytes = try packageSize(url, state: state)
        } else {
            if let identifier = values.fileResourceIdentifier as? AnyHashable,
               !state.claim(identifier) {
                return nil
            }
            bytes = Int64(values.totalFileAllocatedSize ?? 0)
        }
        state.add(bytes: bytes)
        return ScanItem(
            scanner: id, url: url, size: ByteCount(bytes), confidence: .low, lastUsed: lastUsed
        )
    }

    private static func packageSize(_ url: URL, state: State) throws -> Int64 {
        guard let enumerator = FileManager().enumerator(
            at: url, includingPropertiesForKeys: keys, options: []
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            try Task.checkCancellation()
            guard let values = try? file.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true || values.isDirectory == true { continue }
            if let identifier = values.fileResourceIdentifier as? AnyHashable,
               !state.claim(identifier) { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// Keeps the biggest `childLimit` children at or above `minimumNodeSize`, and folds everything
    /// else into one non-actionable block. The block's empty name is the cue for the view to label
    /// it; it can never be selected. The total is preserved exactly.
    static func fold(_ items: [ScanItem], in parent: URL, id: ScannerID, settings: Settings) -> [ScanItem] {
        let sorted = items.sorted { $0.totalSize > $1.totalSize }
        var kept: [ScanItem] = []
        var rest = ByteCount.zero
        for item in sorted {
            if kept.count < settings.childLimit, item.totalSize >= settings.minimumNodeSize {
                kept.append(item)
            } else {
                rest += item.totalSize
            }
        }
        guard rest.bytes > 0 else { return kept }
        let other = ScanItem(
            scanner: id, url: parent, displayName: "", size: rest,
            confidence: .low, blockedReason: .outsideScope
        )
        return (kept + [other]).sorted { $0.totalSize > $1.totalSize }
    }
}
