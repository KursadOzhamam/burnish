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

    @Test("Support directory is named after the bundle, not a literal")
    func supportDirectoryFollowsBundle() throws {
        let identity = AppIdentity(
            bundleIdentifier: "com.example.test",
            displayName: "Renamed",
            version: "1.0",
            build: "1"
        )
        let url = try identity.supportDirectory()
        #expect(url.lastPathComponent == "Renamed")
    }
}

/// Anchor class so the test bundle can be located on both platforms.
private final class Probe {}
