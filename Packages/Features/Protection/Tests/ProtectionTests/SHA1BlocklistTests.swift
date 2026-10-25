import Testing
import Foundation
import CryptoKit
@testable import Protection

/// SHA-1 entries, from lists published as SHA-1, sit beside SHA-256 ones and match by either.
@Suite("SHA-1 blocklist", .serialized)
struct SHA1BlocklistTests {
    private func withRoot(_ body: (URL) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishSHA1-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            // Fixture teardown, not product code.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: root)
        }
        try await body(root)
    }

    private func sha1(_ text: String) -> String {
        Insecure.SHA1.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    @Test("One read gives both digests, matching the reference values, in any chunk size")
    func digests() async throws {
        try await withRoot { root in
            let url = root.appendingPathComponent("a.bin")
            try Data("hello".utf8).write(to: url)
            for chunk in [1, 2, 1_024 * 1_024] {
                let digests = try FileHasher.digests(of: url, chunkSize: chunk)
                #expect(digests.sha1 == "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")
                #expect(digests.sha256 == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
            }
        }
    }

    @Test("A file whose SHA-1 is listed is a threat; one with other content is not")
    func scannerMatchesSHA1() async throws {
        try await withRoot { root in
            try Data("bad content".utf8).write(to: root.appendingPathComponent("bad.sh"))
            try Data("good content".utf8).write(to: root.appendingPathComponent("good.sh"))
            let list = Blocklist(manifest: .init(version: 1, entries: [.init(hash: sha1("bad content"), name: "Test.SHA1")]))
            let findings = try await ProtectionScanner(roots: [root], blocklist: list).scan()
            #expect(findings.map(\.url.lastPathComponent) == ["bad.sh"])
            if case .knownBadHash(let name) = try #require(findings.first).reason { #expect(name == "Test.SHA1") }
        }
    }

    @Test("SHA-1 and SHA-256 entries live in one list and either digest finds the file")
    func mixedList() {
        let digests = FileDigests(sha1: sha1("x"), sha256: String(repeating: "c", count: 64))
        let bySHA1 = Blocklist(manifest: .init(version: 1, entries: [.init(hash: digests.sha1.uppercased(), name: "A")]))
        let bySHA256 = Blocklist(manifest: .init(version: 1, entries: [.init(sha256: digests.sha256, name: "B")]))
        #expect(bySHA1.name(for: digests) == "A")
        #expect(bySHA256.name(for: digests) == "B")
        #expect(Blocklist.empty.name(for: digests) == nil)
    }

    @Test("A list written with the older \"sha256\" field still loads")
    func legacyField() throws {
        let json = Data(#"{"version":2,"entries":[{"sha256":"ABCD","name":"Old"}]}"#.utf8)
        let manifest = try JSONDecoder().decode(Blocklist.Manifest.self, from: json)
        #expect(manifest.entries == [Blocklist.Entry(hash: "abcd", name: "Old")])
        let reencoded = String(decoding: try JSONEncoder().encode(manifest), as: UTF8.self)
        #expect(reencoded.contains("\"hash\""))
    }

    @Test("The list shipped in the app verifies and contains the supplied SHA-1 hashes")
    func shippedList() {
        let list = Blocklist.bundled()
        #expect(list.count >= 232)
        #expect(list.name(forHash: "0168dba214e6ea29db24ef5a1dded935ca01cc4f") != nil)
        #expect(list.name(forHash: "fefec6cae78f79ab8ceae70f45de7834b2a4a892") != nil)
    }
}
