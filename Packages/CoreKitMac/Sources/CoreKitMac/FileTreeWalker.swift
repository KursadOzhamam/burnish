import Foundation
import CoreKit

/// Walks a directory tree and measures it.
///
/// CLAUDE.md §8 is specific about how: `FileManager.enumerator` with the resource keys requested
/// up front, because fetching them lazily turns one `stat` per file into several. Cancellation
/// is checked as it goes, since a scan over a large tree must be stoppable (§8).
///
/// Sizes use `totalFileAllocatedSizeKey` — space actually occupied on disk, not the logical
/// length — so the figure matches what the user gets back. Hard links are counted once; two
/// names for the same inode do not occupy two lots of space, and counting both would overstate
/// the saving (§10.4).
public struct FileTreeWalker: Sendable {

    /// Why a walk could not read what it was pointed at.
    public enum Failure: Error, Sendable, Equatable {
        /// The folder exists but its contents cannot be listed, typically for want of Full Disk
        /// Access (CLAUDE.md §7).
        case unreadable(URL)
    }

    /// One file found during a walk.
    public struct Entry: Sendable, Hashable {
        public let url: URL
        public let size: ByteCount
        public let contentModified: Date?
        public let lastAccessed: Date?
        public let isDirectory: Bool

        public init(
            url: URL,
            size: ByteCount,
            contentModified: Date? = nil,
            lastAccessed: Date? = nil,
            isDirectory: Bool = false
        ) {
            self.url = url
            self.size = size
            self.contentModified = contentModified
            self.lastAccessed = lastAccessed
            self.isDirectory = isDirectory
        }
    }

    /// What a completed walk found.
    public struct Result: Sendable {
        public let totalSize: ByteCount
        public let fileCount: Int
        /// Paths that could not be read. Reported rather than silently dropped, so a scan that
        /// is missing half the tree for want of Full Disk Access can say so (§7).
        public let unreadable: [URL]

        public init(totalSize: ByteCount, fileCount: Int, unreadable: [URL]) {
            self.totalSize = totalSize
            self.fileCount = fileCount
            self.unreadable = unreadable
        }
    }

    private static let resourceKeys: [URLResourceKey] = [
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .fileResourceIdentifierKey,
        .contentModificationDateKey,
        .contentAccessDateKey
    ]

    public init() {}

    /// A fresh `FileManager` per call.
    ///
    /// `FileManager` is not `Sendable`, and the shared instance is only documented as safe for
    /// a subset of operations. Scans run concurrently across roots (§8), so each gets its own.
    private var fileManager: FileManager { FileManager() }

    /// Measures everything beneath `url`.
    ///
    /// - Parameter onProgress: called as the walk advances, for the live path readout (§5.5).
    ///   Called from the walking task, so it must be cheap.
    public func measure(
        _ url: URL,
        isCancelled: () -> Bool = { false },
        onProgress: ((URL, ByteCount) -> Void)? = nil
    ) throws -> Result {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Self.resourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            return Result(totalSize: .zero, fileCount: 0, unreadable: [url])
        }

        var total = ByteCount.zero
        var count = 0
        var unreadable: [URL] = []
        // Inodes already counted, so a hard link is not billed twice.
        var seenIdentifiers = Set<AnyHashable>()

        for case let fileURL as URL in enumerator {
            if isCancelled() { throw CancellationError() }

            guard let values = try? fileURL.resourceValues(forKeys: Set(Self.resourceKeys)) else {
                unreadable.append(fileURL)
                enumerator.skipDescendants()
                continue
            }

            // Symlinks are never followed and never counted: the target is either inside the
            // tree, where it is counted on its own, or outside it, where it is none of our
            // business (CLAUDE.md §4.4).
            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true { continue }

            if let identifier = values.fileResourceIdentifier as? AnyHashable {
                guard seenIdentifiers.insert(identifier).inserted else { continue }
            }

            let bytes = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
            let size = ByteCount(Int64(bytes))
            total += size
            count += 1

            onProgress?(fileURL, total)
        }

        return Result(totalSize: total, fileCount: count, unreadable: unreadable)
    }

    /// Immediate children of `url`, each measured in full.
    ///
    /// Cache folders are organised per application, so the result list shows one row per child
    /// rather than tens of thousands of individual files.
    public func measureChildren(
        of url: URL,
        isCancelled: () -> Bool = { false },
        onProgress: ((URL, ByteCount) -> Void)? = nil
    ) throws -> [Entry] {
        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Self.resourceKeys,
                options: [.skipsHiddenFiles]
            )
        } catch {
            // A folder that is not there holds nothing. One that is there but cannot be read
            // holds something we cannot see, and reporting it as empty is what made the Trash
            // read "0 items" while it held 624 MB.
            guard exists(url) else { return [] }
            throw Failure.unreadable(url)
        }

        var entries: [Entry] = []
        var running = ByteCount.zero

        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if isCancelled() { throw CancellationError() }

            let values = try? child.resourceValues(forKeys: Set(Self.resourceKeys))
            if values?.isSymbolicLink == true { continue }

            let isDirectory = values?.isDirectory ?? false
            let size: ByteCount = if isDirectory {
                try measure(child, isCancelled: isCancelled).totalSize
            } else {
                ByteCount(Int64(values?.totalFileAllocatedSize ?? 0))
            }

            running += size
            onProgress?(child, running)

            entries.append(
                Entry(
                    url: child,
                    size: size,
                    contentModified: values?.contentModificationDate,
                    lastAccessed: values?.contentAccessDate,
                    isDirectory: isDirectory
                )
            )
        }

        return entries
    }

    /// Whether a path exists and can be read at all.
    public func isReadable(_ url: URL) -> Bool {
        fileManager.isReadableFile(atPath: url.path)
    }

    public func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }
}
