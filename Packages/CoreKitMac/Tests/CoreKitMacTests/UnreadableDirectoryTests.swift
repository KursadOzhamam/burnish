import Testing
import Foundation
@testable import CoreKitMac

/// A folder that exists but cannot be listed must not read as empty. This is the bug that made the
/// Trash show "0 items" while holding 624 MB: macOS refuses the listing without Full Disk Access.
/// The tests lock a temporary folder with chmod 000, which fails the same way for the same user.
@Suite("Unreadable directories", .serialized)
struct UnreadableDirectoryTests {

    private func withLockedDirectory(_ body: (URL) throws -> Void) throws {
        let directory = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("BurnishLocked-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: directory.appendingPathComponent("inside.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            // Fixture teardown, not product code.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: directory)
        }
        try body(directory)
    }

    @Test("A directory that exists but cannot be listed throws instead of looking empty")
    func lockedDirectoryThrows() throws {
        try withLockedDirectory { directory in
            #expect(throws: FileTreeWalker.Failure.unreadable(directory)) {
                try FileTreeWalker().measureChildren(of: directory)
            }
        }
    }

    @Test("A directory that does not exist is still just empty")
    func missingDirectoryIsStillEmpty() throws {
        let absent = URL(fileURLWithPath: "/private/tmp/BurnishAbsent-\(UUID().uuidString)")
        #expect(try FileTreeWalker().measureChildren(of: absent).isEmpty)
    }
}

@Suite("Full Disk Access probe", .serialized)
struct FullDiskAccessTests {

    private func makeDirectory(locked: Bool) throws -> URL {
        let directory = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("BurnishProbe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if locked {
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)
        }
        return directory
    }

    private func discard(_ directory: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        // Fixture teardown, not product code.
        // swiftlint:disable:next no_direct_remove_item
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("A readable protected folder means access is granted")
    func readableMeansGranted() throws {
        let directory = try makeDirectory(locked: false)
        defer { discard(directory) }
        #expect(FullDiskAccess.isGranted(probes: [directory]) == true)
    }

    @Test("A folder that exists but cannot be listed means access is missing")
    func lockedMeansDenied() throws {
        let directory = try makeDirectory(locked: true)
        defer { discard(directory) }
        #expect(FullDiskAccess.isGranted(probes: [directory]) == false)
    }

    @Test("When no probe exists nothing can be concluded")
    func noProbeMeansUnknown() {
        let absent = URL(fileURLWithPath: "/private/tmp/BurnishNoProbe-\(UUID().uuidString)")
        #expect(FullDiskAccess.isGranted(probes: [absent]) == nil)
    }

    @Test("Missing probes are skipped and the first existing one decides")
    func firstExistingDecides() throws {
        let absent = URL(fileURLWithPath: "/private/tmp/BurnishNoProbe-\(UUID().uuidString)")
        let locked = try makeDirectory(locked: true)
        defer { discard(locked) }
        #expect(FullDiskAccess.isGranted(probes: [absent, locked]) == false)
    }

    @Test("The settings link targets the Full Disk Access pane")
    func settingsLink() {
        #expect(URL(string: FullDiskAccess.settingsURLString) != nil)
        #expect(FullDiskAccess.settingsURLString.hasSuffix("Privacy_AllFiles"))
    }

    @Test("Default probes live under the given home directory")
    func defaultProbesUseHome() {
        let home = URL(fileURLWithPath: "/Users/tester")
        let probes = FullDiskAccess.defaultProbes(home: home)
        #expect(!probes.isEmpty)
        #expect(probes.allSatisfy { $0.path.hasPrefix("/Users/tester/Library") })
    }
}
