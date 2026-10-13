import Foundation
import CryptoKit
import CoreKit
import ScanEngine

/// Finds files with identical content (CLAUDE.md §6.7).
///
/// Three passes, each cheaper than the next and each discarding what cannot match:
/// 1. group by size (free, comes with the directory listing);
/// 2. compare the first and last 64 KB of what is left;
/// 3. hash the whole file, streaming, only for files that survived both.
///
/// Each result is a group: a container `ScanItem` whose `children` are the identical copies.
/// The container is not actionable (it is not a file); only the copies are. Reports only.
public struct DuplicateScanner: HeavyScanning {
    public let id = ScannerID("files.duplicates")
    public let title: LocalizedStringResource = "files.duplicates.title"

    public let roots: [URL]
    public let minimumSize: ByteCount
    /// Cap on groups returned, biggest waste first.
    public let groupLimit: Int

    private static let edgeBytes = 64 * 1_024
    private static let chunkBytes = 1_024 * 1_024
    /// Folders whose duplicates are expected and harmless to leave alone: the same package
    /// installed in ten projects is how `node_modules` works, and removing a copy breaks a build.
    private static let skippedFolderNames: Set<String> = ["node_modules", ".git", ".build", ".venv"]

    public init(
        roots: [URL],
        minimumSize: ByteCount = ByteCount(1_048_576),
        groupLimit: Int = 300
    ) {
        self.roots = roots
        self.minimumSize = minimumSize
        self.groupLimit = groupLimit
    }

    struct Candidate {
        let url: URL
        let size: Int64
        let modified: Date?
    }

    public func scan(
        progress: @Sendable (ScanProgress) -> Void,
        partial: @Sendable ([ScanItem]) -> Void
    ) async throws -> [ScanItem] {
        try run(progress: progress, partial: partial)
    }

    // Synchronous: DirectoryEnumerator cannot be iterated from async code. Cancellation is
    // checked per file and per chunk.
    private func run(
        progress: @Sendable (ScanProgress) -> Void,
        partial: @Sendable ([ScanItem]) -> Void
    ) throws -> [ScanItem] {
        // Pass 1: list and group by size.
        let bySize = try collect(progress: progress)
        let sizeGroups = bySize.values.filter { $0.count >= 2 }
        let pending = sizeGroups.reduce(Int64(0)) { $0 + $1.reduce(0) { $0 + $1.size } }

        // Pass 2: edges. Pass 3: full hash. Progress is bytes read of what is still to read.
        var read: Int64 = 0
        var groups: [ScanItem] = []
        var found = 0

        for group in sizeGroups.sorted(by: { $0[0].size > $1[0].size }) {
            try Task.checkCancellation()
            let size = group[0].size

            var byEdges: [Data: [Candidate]] = [:]
            for candidate in group {
                try Task.checkCancellation()
                let key = try edgeDigest(of: candidate)
                read += min(size, Int64(Self.edgeBytes * 2))
                byEdges[key, default: []].append(candidate)
            }

            for survivors in byEdges.values where survivors.count >= 2 {
                var byHash: [Data: [Candidate]] = [:]
                for candidate in survivors {
                    try Task.checkCancellation()
                    byHash[try fullDigest(of: candidate, onChunk: { chunk in
                        read += chunk
                        progress(
                            ScanProgress(
                                fraction: pending > 0 ? min(0.99, Double(read) / Double(pending)) : nil,
                                currentPath: candidate.url.path,
                                discovered: ByteCount(Self.wasted(groups)),
                                itemCount: found
                            )
                        )
                    }), default: []].append(candidate)
                }
                for identical in byHash.values where identical.count >= 2 {
                    groups.append(makeGroup(identical))
                    found += 1
                }
            }
            groups.sort { $0.wasted > $1.wasted }
            if groups.count > groupLimit { groups.removeLast(groups.count - groupLimit) }
            partial(groups)
        }

        progress(ScanProgress(fraction: 1, discovered: ByteCount(Self.wasted(groups)), itemCount: groups.count))
        return groups
    }

    // MARK: Pass 1

    private func collect(progress: @Sendable (ScanProgress) -> Void) throws -> [Int64: [Candidate]] {
        let keys: [URLResourceKey] = [
            .totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
            .isPackageKey, .isDirectoryKey, .fileResourceIdentifierKey, .contentModificationDateKey
        ]
        var bySize: [Int64: [Candidate]] = [:]
        var seen = Set<AnyHashable>()
        var visited = 0

        for root in roots {
            guard let enumerator = FileManager().enumerator(
                at: root, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                visited += 1
                if visited % 512 == 0 {
                    try Task.checkCancellation()
                    progress(ScanProgress(fraction: nil, currentPath: url.path, itemCount: visited))
                }
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                if values.isDirectory == true, Self.skippedFolderNames.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }
                if values.isSymbolicLink == true || values.isPackage == true { continue }
                guard values.isRegularFile == true else { continue }

                // Real size in bytes (not disk blocks): equal content means equal length.
                let size = Int64(values.fileSize ?? 0)
                // Empty files are all identical and free nothing, whatever the minimum says.
                guard size > 0, size >= minimumSize.bytes else { continue }

                // Two names for one file on disk are not duplicates: nothing would be freed.
                if let identifier = values.fileResourceIdentifier as? AnyHashable,
                   !seen.insert(identifier).inserted { continue }

                bySize[size, default: []].append(
                    Candidate(url: url, size: size, modified: values.contentModificationDate)
                )
            }
        }
        return bySize
    }

    // MARK: Passes 2 and 3

    private func edgeDigest(of candidate: Candidate) throws -> Data {
        guard let handle = try? FileHandle(forReadingFrom: candidate.url) else { return Data() }
        defer { try? handle.close() }
        var hasher = SHA256()
        let head = try handle.read(upToCount: Self.edgeBytes) ?? Data()
        hasher.update(data: head)
        if candidate.size > Int64(Self.edgeBytes) {
            try handle.seek(toOffset: UInt64(max(0, candidate.size - Int64(Self.edgeBytes))))
            hasher.update(data: try handle.read(upToCount: Self.edgeBytes) ?? Data())
        }
        return Data(hasher.finalize())
    }

    private func fullDigest(of candidate: Candidate, onChunk: (Int64) -> Void) throws -> Data {
        guard let handle = try? FileHandle(forReadingFrom: candidate.url) else { return Data() }
        defer { try? handle.close() }
        var hasher = SHA256()
        // A buffer at a time: a file is never held in memory whole (CLAUDE.md §8).
        while true {
            try Task.checkCancellation()
            let chunk = try autoreleasepool { try handle.read(upToCount: Self.chunkBytes) ?? Data() }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            onChunk(Int64(chunk.count))
        }
        return Data(hasher.finalize())
    }

    // MARK: Results

    private func makeGroup(_ copies: [Candidate]) -> ScanItem {
        let items = copies
            .sorted { ($0.modified ?? .distantFuture) < ($1.modified ?? .distantFuture) }
            .map {
                ScanItem(scanner: id, url: $0.url, size: ByteCount($0.size), confidence: .low, lastUsed: $0.modified)
            }
        return ScanItem(
            scanner: id, url: items[0].url, displayName: items[0].displayName, size: .zero,
            confidence: .low, children: items, blockedReason: .outsideScope
        )
    }

    fileprivate static func wasted(_ groups: [ScanItem]) -> Int64 {
        groups.reduce(0) { $0 + $1.wasted }
    }
}

extension ScanItem {
    /// For a group of duplicates or look-alikes: the space freed if everything but the largest
    /// member were removed. For identical files that is simply all copies but one.
    public var wasted: Int64 {
        guard children.count >= 2, let largest = children.map(\.size.bytes).max() else { return 0 }
        return children.reduce(0) { $0 + $1.size.bytes } - largest
    }
}
