import Foundation
import CoreKit
import ScanEngine

/// Finds pictures that look alike (CLAUDE.md §6.7): bursts and near-identical retakes.
///
/// Uses Vision feature prints on a reduced copy of each image, so nothing leaves the machine and
/// no full-size original is held in memory. Results are groups, like the duplicate finder's: a
/// non-actionable container whose `children` are the pictures. Reports only.
public struct SimilarImagesScanner: HeavyScanning {
    public let id = ScannerID("files.similarImages")
    public let title: LocalizedStringResource = "files.similar.title"

    public let roots: [URL]
    /// Pictures smaller than this are icons and thumbnails, not photos.
    public let minimumSize: ByteCount
    /// Feature-print distance under which two pictures count as the same shot.
    public let threshold: Float
    /// How many following pictures (in capture order) each one is compared with.
    public let window: Int
    /// Upper bound, so a very large collection cannot exhaust memory with feature prints.
    public let imageLimit: Int
    public let groupLimit: Int

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff"]
    private static let skippedFolderNames: Set<String> = ["node_modules", ".git", ".build", ".venv"]

    public init(
        roots: [URL],
        minimumSize: ByteCount = ByteCount(50 * 1_024),
        threshold: Float = 0.35,
        window: Int = 40,
        imageLimit: Int = 20_000,
        groupLimit: Int = 300
    ) {
        self.roots = roots
        self.minimumSize = minimumSize
        self.threshold = threshold
        self.window = window
        self.imageLimit = imageLimit
        self.groupLimit = groupLimit
    }

    struct Picture {
        let url: URL
        let size: Int64
        let taken: Date
    }

    public func scan(
        progress: @Sendable (ScanProgress) -> Void,
        partial: @Sendable ([ScanItem]) -> Void
    ) async throws -> [ScanItem] {
        let pictures = try Self.list(roots: roots, minimumSize: minimumSize, limit: imageLimit, progress: progress)
        let id = self.id
        let threshold = self.threshold
        let window = self.window
        let groupLimit = self.groupLimit

        // Feature prints, a few at a time: the work is CPU-bound and each task is one picture.
        var prints = [FeaturePrint?](repeating: nil, count: pictures.count)
        var done = 0
        let lanes = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)

        try await withThrowingTaskGroup(of: (Int, FeaturePrint?).self) { group in
            var next = 0
            func launch() {
                guard next < pictures.count else { return }
                let index = next
                next += 1
                let url = pictures[index].url
                group.addTask {
                    try Task.checkCancellation()
                    return (index, ImageFeatures.featurePrint(of: url))
                }
            }
            for _ in 0..<lanes { launch() }

            for try await (index, print) in group {
                prints[index] = print
                done += 1
                launch()
                progress(
                    ScanProgress(
                        fraction: Double(done) / Double(max(1, pictures.count)),
                        currentPath: pictures[index].url.path,
                        itemCount: done
                    )
                )
                // A partial answer every so often, from what has been analysed so far.
                if done % 250 == 0 {
                    partial(Self.makeGroups(pictures, prints, id: id, threshold: threshold, window: window, limit: groupLimit))
                }
            }
        }

        let result = Self.makeGroups(pictures, prints, id: id, threshold: threshold, window: window, limit: groupLimit)
        progress(ScanProgress(fraction: 1, itemCount: result.count))
        return result
    }

    // MARK: Listing (synchronous: DirectoryEnumerator cannot be iterated from async code)

    private static func list(
        roots: [URL], minimumSize: ByteCount, limit: Int, progress: @Sendable (ScanProgress) -> Void
    ) throws -> [Picture] {
        let keys: [URLResourceKey] = [
            .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey, .isDirectoryKey,
            .fileResourceIdentifierKey, .contentModificationDateKey, .creationDateKey
        ]
        var pictures: [Picture] = []
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
                    progress(ScanProgress(fraction: nil, currentPath: url.path, itemCount: pictures.count))
                }
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                if values.isDirectory == true, skippedFolderNames.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }
                if values.isSymbolicLink == true || values.isPackage == true { continue }
                guard values.isRegularFile == true,
                      imageExtensions.contains(url.pathExtension.lowercased()) else { continue }
                let size = Int64(values.fileSize ?? 0)
                guard size >= minimumSize.bytes, size > 0 else { continue }
                if let identifier = values.fileResourceIdentifier as? AnyHashable,
                   !seen.insert(identifier).inserted { continue }
                let taken = values.creationDate ?? values.contentModificationDate ?? .distantPast
                pictures.append(Picture(url: url, size: size, taken: taken))
                if pictures.count >= limit { break }
            }
        }
        // Capture order is what makes the neighbour window meaningful.
        return pictures.sorted { $0.taken < $1.taken }
    }

    // MARK: Grouping

    static func makeGroups(
        _ pictures: [Picture], _ prints: [FeaturePrint?], id: ScannerID,
        threshold: Float, window: Int, limit: Int
    ) -> [ScanItem] {
        let indices = SimilarityGrouping.groups(count: pictures.count, window: window) { first, second in
            guard let a = prints[first], let b = prints[second], let distance = a.distance(to: b) else { return false }
            return distance < threshold
        }
        let groups: [ScanItem] = indices.map { members in
            let copies = members.map { index in
                ScanItem(
                    scanner: id, url: pictures[index].url, size: ByteCount(pictures[index].size),
                    confidence: .low, lastUsed: pictures[index].taken
                )
            }
            return ScanItem(
                scanner: id, url: copies[0].url, displayName: copies[0].displayName, size: .zero,
                confidence: .low, children: copies, blockedReason: .outsideScope
            )
        }
        return Array(groups.sorted { $0.wasted > $1.wasted }.prefix(limit))
    }
}
