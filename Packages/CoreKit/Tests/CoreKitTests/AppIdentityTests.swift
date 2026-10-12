import Testing
import Foundation
@testable import CoreKit

@Suite("AppIdentity")
struct AppIdentityTests {
    @Test("Missing Info.plist keys fall back instead of crashing")
    func fallsBackForEmptyBundle() {
        let identity = AppIdentity(bundle: Bundle(for: Probe.self))
        #expect(!identity.displayName.isEmpty)
        #expect(!identity.version.isEmpty)
        #expect(!identity.build.isEmpty)
    }

    @Test("Version description combines version and build")
    func versionDescription() {
        let identity = AppIdentity(
            bundleIdentifier: "com.example.test",
            displayName: "Example",
            version: "1.2.3",
            build: "45"
        )
        #expect(identity.versionDescription == "1.2.3 (45)")
    }

    private func withTemporaryBase(_ body: (URL) throws -> Void) throws {
        let base = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("BurnishSupport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // Fixture teardown, not product code.
        // swiftlint:disable:next no_direct_remove_item
        defer { try? FileManager.default.removeItem(at: base) }
        try body(base)
    }

    private func identity(named name: String) -> AppIdentity {
        AppIdentity(bundleIdentifier: "com.example.test", displayName: name, version: "1.0", build: "1")
    }

    @Test("Support directory is named after the bundle, not a literal")
    func supportDirectoryFollowsBundle() throws {
        try withTemporaryBase { base in
            let url = try identity(named: "Renamed").supportDirectory(under: base)
            #expect(url.lastPathComponent == "Renamed")
        }
    }

    @Test("Support directory actually exists afterwards — the history database lives in it")
    func supportDirectoryIsCreated() throws {
        try withTemporaryBase { base in
            let url = try identity(named: "Fresh").supportDirectory(under: base)

            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            #expect(exists && isDirectory.boolValue,
                    "a path that does not exist cannot hold history.sqlite")
        }
    }

    @Test("Asking twice is harmless and keeps existing contents")
    func supportDirectoryIsIdempotent() throws {
        try withTemporaryBase { base in
            let first = try identity(named: "Again").supportDirectory(under: base)
            let marker = first.appendingPathComponent("keep.txt")
            try Data("x".utf8).write(to: marker)

            let second = try identity(named: "Again").supportDirectory(under: base)

            #expect(first == second)
            #expect(FileManager.default.fileExists(atPath: marker.path))
        }
    }
}

/// Anchor class so the test bundle can be located on both platforms.
private final class Probe {}
