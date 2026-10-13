import Testing
import Foundation
@testable import Files

@Suite("Scan scope")
@MainActor
struct ScanScopeTests {
    private func makeFolders() throws -> (URL, [URL]) {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishScope-\(UUID().uuidString)")
        let folders = ["a", "b"].map { root.appendingPathComponent($0) }
        for folder in folders { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        return (root, folders)
    }

    private func cleanUp(_ root: URL) {
        // Fixture teardown, not product code.
        // swiftlint:disable:next no_direct_remove_item
        try? FileManager.default.removeItem(at: root)
    }

    private func suite() -> UserDefaults {
        let name = "BurnishScopeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Defaults are all enabled; switching one off removes it from the roots")
    func toggling() throws {
        let (root, folders) = try makeFolders()
        defer { cleanUp(root) }
        let scope = ScanScope(roots: folders)
        #expect(scope.roots.count == 2)
        scope.setEnabled(false, for: folders[0])
        #expect(scope.roots.map(\.lastPathComponent) == ["b"])
    }

    @Test("An added folder is searched; a built-in one cannot be removed, only switched off")
    func addAndRemove() throws {
        let (root, folders) = try makeFolders()
        defer { cleanUp(root) }
        let extra = root.appendingPathComponent("extra")
        try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        let scope = ScanScope(roots: folders)
        scope.add(extra)
        #expect(scope.roots.contains { $0.lastPathComponent == "extra" })
        scope.remove(extra)
        #expect(!scope.candidates.contains { $0.lastPathComponent == "extra" })
        scope.remove(folders[0])
        #expect(scope.candidates.contains { $0.path == folders[0].path }, "built-in folders stay")
    }

    @Test("A folder that no longer exists drops out of the roots")
    func missingDropped() throws {
        let (root, folders) = try makeFolders()
        let scope = ScanScope(roots: folders)
        cleanUp(root)
        #expect(scope.roots.isEmpty)
    }

    @Test("Choices persist across instances")
    func persists() throws {
        let (root, folders) = try makeFolders()
        defer { cleanUp(root) }
        let defaults = suite()
        let extra = root.appendingPathComponent("extra")
        try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)

        let first = ScanScope(defaultRoots: folders, defaults: defaults)
        first.add(extra)
        first.setEnabled(false, for: folders[1])
        first.exclude(root.appendingPathComponent("a/skip"))

        let second = ScanScope(defaultRoots: folders, defaults: defaults)
        #expect(second.candidates.contains { $0.lastPathComponent == "extra" })
        #expect(!second.isEnabled(folders[1]))
        #expect(second.excluded.map(\.lastPathComponent) == ["skip"])
    }

    @Test("Exclusion matches the folder and everything inside, not a lookalike name")
    func exclusionMatching() {
        let paths = ["/Users/x/Projects"]
        #expect(isExcluded(URL(fileURLWithPath: "/Users/x/Projects"), by: paths))
        #expect(isExcluded(URL(fileURLWithPath: "/Users/x/Projects/app/file"), by: paths))
        #expect(!isExcluded(URL(fileURLWithPath: "/Users/x/Projects-old"), by: paths))
        #expect(!isExcluded(URL(fileURLWithPath: "/Users/x/Other"), by: paths))
    }

    @Test("Excluding the same folder twice lists it once; including brings it back")
    func excludeTwice() throws {
        let scope = ScanScope(roots: [])
        let url = URL(fileURLWithPath: "/private/tmp/skip")
        scope.exclude(url)
        scope.exclude(url)
        #expect(scope.excluded.count == 1)
        scope.include(url)
        #expect(scope.excluded.isEmpty)
    }
}

@Suite("Exclusions in scanners", .serialized)
struct ScannerExclusionTests {
    @Test("Large files does not enter an excluded folder")
    func largeFiles() async throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishExcl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("skip"), withIntermediateDirectories: true)
        defer {
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: root)
        }
        try Data(repeating: 1, count: 2_000_000).write(to: root.appendingPathComponent("skip/big.bin"))
        try Data(repeating: 1, count: 2_000_000).write(to: root.appendingPathComponent("keep.bin"))
        let scanner = LargeFilesScanner(
            roots: [root], minimumSize: .init(1_000_000), excludedPaths: [root.appendingPathComponent("skip").path]
        )
        let names = try await scanner.scan { _ in }.map(\.displayName)
        #expect(names == ["keep.bin"])
    }

    @Test("Space map leaves an excluded folder out of the tree")
    func spaceMap() async throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishExclMap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("skip"), withIntermediateDirectories: true)
        defer {
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: root)
        }
        try Data(repeating: 1, count: 2_000_000).write(to: root.appendingPathComponent("skip/big.bin"))
        try Data(repeating: 1, count: 2_000_000).write(to: root.appendingPathComponent("keep.bin"))
        let scanner = SpaceLensScanner(root: root, minimumNodeSize: .zero, excludedPaths: [root.appendingPathComponent("skip").path])
        let tree = try #require(try await scanner.scan { _ in }.first)
        #expect(tree.children.map { $0.url.lastPathComponent } == ["keep.bin"])
    }
}
