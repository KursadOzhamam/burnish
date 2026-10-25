import Testing
import Foundation
import CryptoKit
@testable import Protection

/// The shipped hash list is used only when its signature verifies.
@Suite("Bundled blocklist", .serialized)
struct BundledBlocklistTests {
    private let key = Curve25519.Signing.PrivateKey()
    private let hash = String(repeating: "ab", count: 32)

    /// Writes `blocklist.json` and `blocklist.sig` into a fresh folder and opens it as a bundle.
    private func withBundle(
        payload: Data? = nil, signature: Data? = nil, _ body: (Bundle) throws -> Void
    ) throws {
        let folder = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishBlocklist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            // Fixture teardown, not product code.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: folder)
        }
        let manifest = Blocklist.Manifest(version: 20261026, entries: [Blocklist.Entry(sha256: hash, name: "AMOS")])
        let bytes = try payload ?? JSONEncoder().encode(manifest)
        try bytes.write(to: folder.appendingPathComponent("blocklist.json"))
        try (signature ?? key.signature(for: bytes)).write(to: folder.appendingPathComponent("blocklist.sig"))
        try body(try #require(Bundle(url: folder)))
    }

    @Test("A correctly signed list is loaded")
    func loadsSignedList() throws {
        try withBundle { bundle in
            let list = Blocklist.bundled(bundle: bundle, publicKey: key.publicKey)
            #expect(list.count == 1)
            #expect(list.version == 20261026)
            #expect(list.name(forHash: hash.uppercased()) == "AMOS")
        }
    }

    @Test("A list signed by another key is ignored")
    func wrongKey() throws {
        try withBundle { bundle in
            #expect(Blocklist.bundled(bundle: bundle, publicKey: Curve25519.Signing.PrivateKey().publicKey).count == 0)
        }
    }

    @Test("An edited list is ignored: tampering can only empty it, never change it")
    func tampered() throws {
        let original = try JSONEncoder().encode(Blocklist.Manifest(version: 1, entries: []))
        let signature = try key.signature(for: original)
        let edited = try JSONEncoder().encode(
            Blocklist.Manifest(version: 1, entries: [Blocklist.Entry(sha256: hash, name: "x")])
        )
        try withBundle(payload: edited, signature: signature) { bundle in
            #expect(Blocklist.bundled(bundle: bundle, publicKey: key.publicKey).count == 0)
        }
    }

    @Test("Without a key nothing is loaded")
    func noKey() throws {
        try withBundle { bundle in
            #expect(Blocklist.bundled(bundle: bundle, publicKey: nil).count == 0)
        }
    }

    @Test("The configured public key is a valid Ed25519 key")
    func configuredKey() {
        #expect(BlocklistConfiguration.publicKey != nil)
    }
}
