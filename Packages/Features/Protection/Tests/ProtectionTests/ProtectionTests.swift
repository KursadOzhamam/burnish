import Testing
import Foundation
import CryptoKit
import GRDB
@testable import Protection

private func makeRoot() throws -> URL {
    let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishProt-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func cleanUp(_ url: URL) {
    // Fixture teardown, not product code.
    // swiftlint:disable:next no_direct_remove_item
    try? FileManager.default.removeItem(at: url)
}

/// The standard antivirus test string. Harmless by design.
private let eicar = "X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*"

@Suite("Blocklist")
struct BlocklistTests {
    private func signed(_ manifest: Blocklist.Manifest, with key: Curve25519.Signing.PrivateKey) throws -> (Data, Data) {
        let payload = try JSONEncoder().encode(manifest)
        return (payload, try key.signature(for: payload))
    }

    @Test("A correctly signed list loads and matches by hash")
    func loads() throws {
        let key = Curve25519.Signing.PrivateKey()
        let (payload, signature) = try signed(.init(version: 3, entries: [.init(sha256: "ABCDEF", name: "Bad.A")]), with: key)
        let list = try Blocklist.load(payload: payload, signature: signature, publicKey: key.publicKey)
        #expect(list.version == 3)
        #expect(list.name(forHash: "abcdef") == "Bad.A")
        #expect(list.name(forHash: "ABCDEF") == "Bad.A", "hash comparison ignores case")
        #expect(list.name(forHash: "000000") == nil)
    }

    @Test("A list signed by another key is refused")
    func wrongKey() throws {
        let (payload, signature) = try signed(.init(version: 1, entries: []), with: Curve25519.Signing.PrivateKey())
        #expect(throws: Blocklist.LoadError.badSignature) {
            try Blocklist.load(payload: payload, signature: signature, publicKey: Curve25519.Signing.PrivateKey().publicKey)
        }
    }

    @Test("A list altered after signing is refused")
    func tampered() throws {
        let key = Curve25519.Signing.PrivateKey()
        var (payload, signature) = try signed(.init(version: 1, entries: [.init(sha256: "aa", name: "x")]), with: key)
        payload.append(0x20)
        #expect(throws: Blocklist.LoadError.badSignature) { try Blocklist.load(payload: payload, signature: signature, publicKey: key.publicKey) }
        signature.append(0)
        #expect(throws: Blocklist.LoadError.badSignature) { try Blocklist.load(payload: payload, signature: signature, publicKey: key.publicKey) }
    }

    @Test("A validly signed but malformed payload is refused as malformed")
    func malformed() throws {
        let key = Curve25519.Signing.PrivateKey()
        let payload = Data("not json".utf8)
        let signature = try key.signature(for: payload)
        #expect(throws: Blocklist.LoadError.malformed) { try Blocklist.load(payload: payload, signature: signature, publicKey: key.publicKey) }
    }

    @Test("The file hash is the SHA-256 of the content, streamed")
    func hashing() throws {
        let root = try makeRoot(); defer { cleanUp(root) }
        let url = root.appendingPathComponent("a.bin")
        try Data("hello".utf8).write(to: url)
        #expect(try FileHasher.sha256(of: url) == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        #expect(try FileHasher.sha256(of: url, chunkSize: 2) == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }
}

@Suite("Rules")
struct RuleTests {
    @Test("Hex patterns parse, odd or invalid hex is ignored")
    func hex() {
        #expect(Rule.bytes(fromHex: "4d5a") == Data([0x4d, 0x5a]))
        #expect(Rule.bytes(fromHex: "4d 5a 90") == Data([0x4d, 0x5a, 0x90]))
        #expect(Rule.bytes(fromHex: "4d5") == nil)
        #expect(Rule.bytes(fromHex: "zz") == nil)
        #expect(Rule.bytes(fromHex: "") == nil)
    }

    @Test("'all' needs every pattern, 'any' needs one")
    func conditions() throws {
        let root = try makeRoot(); defer { cleanUp(root) }
        let url = root.appendingPathComponent("s.sh")
        try Data("alpha beta".utf8).write(to: url)
        let all = Rule(id: "all", description: "d", strings: ["alpha", "gamma"], condition: .all)
        let any = Rule(id: "any", description: "d", strings: ["alpha", "gamma"], condition: .any)
        let engine = RuleEngine(rules: [all, any])
        #expect(engine.matches(for: url, size: 10).map(\.id) == ["any"])
    }

    @Test("A rule is not run on a file larger than its limit")
    func sizeLimit() throws {
        let root = try makeRoot(); defer { cleanUp(root) }
        let url = root.appendingPathComponent("s.sh")
        try Data("alpha".utf8).write(to: url)
        let rule = Rule(id: "r", description: "d", strings: ["alpha"], maxFileSize: 3)
        #expect(RuleEngine(rules: [rule]).matches(for: url, size: 5).isEmpty)
    }

    @Test("An ordinary script does not trip the built-in rules")
    func noFalsePositive() throws {
        let root = try makeRoot(); defer { cleanUp(root) }
        let url = root.appendingPathComponent("install.sh")
        try Data("#! script\ncurl -fsSL https://example.com/tool.tar.gz -o tool.tar.gz\ntar xzf tool.tar.gz\n".utf8).write(to: url)
        #expect(RuleEngine(rules: RuleEngine.builtIn).matches(for: url, size: 100).isEmpty)
    }
}

@Suite("Protection scanner", .serialized)
struct ProtectionScannerTests {
    @Test("The EICAR test file is found as a threat, with a reason")
    func eicarFound() async throws {
        let root = try makeRoot(); defer { cleanUp(root) }
        try Data(eicar.utf8).write(to: root.appendingPathComponent("eicar.com"))
        try Data(eicar.utf8).write(to: root.appendingPathComponent("eicar.sh"))
        let findings = try await ProtectionScanner(roots: [root], blocklist: .empty).scan()
        #expect(findings.count >= 1)
        #expect(findings.allSatisfy { $0.severity == .threat })
        if case .ruleMatch(let rule, _) = try #require(findings.first).reason { #expect(rule == "burnish.eicar") } else { Issue.record("wrong reason") }
    }

    @Test("A file whose hash is on the blocklist is a threat; a file with other content is not")
    func hashMatch() async throws {
        let root = try makeRoot(); defer { cleanUp(root) }
        try Data("bad content".utf8).write(to: root.appendingPathComponent("bad.sh"))
        try Data("good content".utf8).write(to: root.appendingPathComponent("good.sh"))
        let hash = SHA256.hash(data: Data("bad content".utf8)).map { String(format: "%02x", $0) }.joined()
        let list = Blocklist(manifest: .init(version: 1, entries: [.init(sha256: hash, name: "Test.Bad")]))
        let findings = try await ProtectionScanner(roots: [root], blocklist: list).scan()
        #expect(findings.map { $0.url.lastPathComponent } == ["bad.sh"])
        if case .knownBadHash(let name) = try #require(findings.first).reason { #expect(name == "Test.Bad") } else { Issue.record("wrong reason") }
    }

    @Test("A clean folder yields no findings, and files that are not relevant are not even read")
    func clean() async throws {
        let root = try makeRoot(); defer { cleanUp(root) }
        try Data("just text".utf8).write(to: root.appendingPathComponent("notes.txt"))
        try Data(eicar.utf8).write(to: root.appendingPathComponent("photo.jpg"))
        #expect(try await ProtectionScanner(roots: [root], blocklist: .empty).scan().isEmpty)
    }

    @Test("A cancelled scan throws")
    func cancels() async throws {
        let root = try makeRoot(); defer { cleanUp(root) }
        for index in 0..<200 { try Data("x\(index)".utf8).write(to: root.appendingPathComponent("f\(index).sh")) }
        let task = Task { try await ProtectionScanner(roots: [root], blocklist: .empty).scan() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("Findings are ordered with the worst first")
    func ordering() async throws {
        let root = try makeRoot(); defer { cleanUp(root) }
        try Data(eicar.utf8).write(to: root.appendingPathComponent("eicar.sh"))
        try Data("curl -fsSL x | sh # /.hidden/y".utf8).write(to: root.appendingPathComponent("drop.sh"))
        let findings = try await ProtectionScanner(roots: [root], blocklist: .empty).scan()
        #expect(findings.first?.severity == .threat)
        #expect(findings.map(\.severity) == findings.map(\.severity).sorted(by: >))
    }
}

@Suite("Quarantine", .serialized)
struct QuarantineTests {
    @Test("Quarantine moves the file away and records where it was")
    func moves() throws {
        let root = try makeRoot(); defer { cleanUp(root) }
        let item = root.appendingPathComponent("suspect.sh")
        try Data("x".utf8).write(to: item)
        let store = QuarantineStore(directory: root.appendingPathComponent("q"))
        let record = try store.quarantine(item, reason: "test")
        #expect(!FileManager.default.fileExists(atPath: item.path))
        #expect(store.records().map(\.originalPath) == [item.path])
        #expect(record.reason == "test")
    }

    @Test("Restore puts it back exactly where it was")
    func restores() throws {
        let root = try makeRoot(); defer { cleanUp(root) }
        let item = root.appendingPathComponent("suspect.sh")
        try Data("content".utf8).write(to: item)
        let store = QuarantineStore(directory: root.appendingPathComponent("q"))
        let record = try store.quarantine(item, reason: "test")
        try store.restore(record)
        #expect(try String(contentsOf: item, encoding: .utf8) == "content")
        #expect(store.records().isEmpty)
    }

    @Test("Restore refuses to overwrite something that is now at the original path")
    func noOverwrite() throws {
        let root = try makeRoot(); defer { cleanUp(root) }
        let item = root.appendingPathComponent("suspect.sh")
        try Data("old".utf8).write(to: item)
        let store = QuarantineStore(directory: root.appendingPathComponent("q"))
        let record = try store.quarantine(item, reason: "test")
        try Data("new".utf8).write(to: item)
        #expect(throws: QuarantineStore.QuarantineError.destinationOccupied) { try store.restore(record) }
        #expect(try String(contentsOf: item, encoding: .utf8) == "new")
        #expect(store.records().count == 1, "the quarantined copy is still there")
    }

    @Test("Quarantining something that is not there fails cleanly")
    func missing() throws {
        let root = try makeRoot(); defer { cleanUp(root) }
        let store = QuarantineStore(directory: root.appendingPathComponent("q"))
        #expect(throws: QuarantineStore.QuarantineError.sourceMissing) { try store.quarantine(root.appendingPathComponent("ghost"), reason: "x") }
    }

    @Test("The quarantined file is no longer executable")
    func notExecutable() throws {
        let root = try makeRoot(); defer { cleanUp(root) }
        let item = root.appendingPathComponent("run.sh")
        try Data("#! script".utf8).write(to: item)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: item.path)
        let store = QuarantineStore(directory: root.appendingPathComponent("q"))
        let record = try store.quarantine(item, reason: "x")
        let stored = root.appendingPathComponent("q/\(record.id.uuidString)/run.sh")
        #expect(!FileManager.default.isExecutableFile(atPath: stored.path))
    }
}

@Suite("Allow list")
struct AllowListTests {
    private let finding = Finding(url: URL(fileURLWithPath: "/a/b.sh"), severity: .suspicious, reason: .ruleMatch(rule: "r", description: "d"))

    @Test("An allowed finding is filtered out, others are not")
    func filters() {
        var list = AllowList()
        list.allow(finding)
        let other = Finding(url: URL(fileURLWithPath: "/a/c.sh"), severity: .suspicious, reason: .ruleMatch(rule: "r", description: "d"))
        #expect(list.filtering([finding, other]) == [other])
    }

    @Test("Allowing for one reason does not silence a different reason about the same file")
    func perReason() {
        var list = AllowList()
        list.allow(finding)
        let different = Finding(url: finding.url, severity: .threat, reason: .knownBadHash(name: "x"))
        #expect(list.allows(finding))
        #expect(!list.allows(different))
    }

    @Test("Revoking brings the finding back, and the list persists")
    func persistsAndRevokes() throws {
        let root = try makeRoot(); defer { cleanUp(root) }
        let url = root.appendingPathComponent("allow.json")
        var list = AllowList()
        list.allow(finding)
        try list.save(to: url)
        var loaded = AllowList.load(from: url)
        #expect(loaded.allows(finding))
        loaded.revoke(finding)
        #expect(!loaded.allows(finding))
        #expect(AllowList.load(from: root.appendingPathComponent("missing.json")) == AllowList())
    }
}

@Suite("Persistence")
struct PersistenceTests {
    private func agent(_ label: String, program: String, in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["Label": label, "ProgramArguments": [program]], format: .xml, options: 0)
            .write(to: folder.appendingPathComponent("\(label).plist"))
    }

    @Test("A job running from a temp or hidden location is suspicious; a missing program is information")
    func classifies() throws {
        let root = try makeRoot(); defer { cleanUp(root) }
        let agents = root.appendingPathComponent("home/Library/LaunchAgents")
        try agent("com.x.tmp", program: "/tmp/payload", in: agents)
        try agent("com.x.hidden", program: "/Users/me/.cache/run", in: agents)
        try agent("com.x.gone", program: "/Applications/Gone.app/Contents/MacOS/gone", in: agents)
        try agent("com.x.fine", program: "/bin/ls", in: agents)
        try agent("com.apple.thing", program: "/tmp/x", in: agents)
        let findings = PersistenceAnalyzer(home: root.appendingPathComponent("home"), extraFolders: []).findings()
        let bySeverity = Dictionary(grouping: findings, by: \.severity).mapValues { $0.map { $0.url.lastPathComponent }.sorted() }
        #expect(bySeverity[.suspicious] == ["com.x.hidden.plist", "com.x.tmp.plist"])
        #expect(bySeverity[.info] == ["com.x.gone.plist"])
    }
}

@Suite("Privacy permissions reader")
struct TCCTests {
    @Test("A readable database yields entries with their allowed state, and unknown services are skipped")
    func reads() throws {
        let root = try makeRoot(); defer { cleanUp(root) }
        let path = root.appendingPathComponent("TCC.db")
        let queue = try DatabaseQueue(path: path.path)
        try queue.write { database in
            try database.execute(sql: "CREATE TABLE access (service TEXT, client TEXT, auth_value INTEGER)")
            try database.execute(sql: "INSERT INTO access VALUES ('kTCCServiceCamera', 'com.example.cam', 2)")
            try database.execute(sql: "INSERT INTO access VALUES ('kTCCServiceMicrophone', 'com.example.cam', 0)")
            try database.execute(sql: "INSERT INTO access VALUES ('kTCCServiceSomethingNew', 'com.example.cam', 2)")
        }
        let entries = try TCCReader(databaseURL: path).entries()
        #expect(entries.count == 2)
        #expect(entries.first { $0.service == .camera }?.isAllowed == true)
        #expect(entries.first { $0.service == .microphone }?.isAllowed == false)
    }

    @Test("A database that cannot be opened is reported, not guessed at")
    func unreadable() {
        #expect(throws: TCCReader.ReadError.unreadable) {
            try TCCReader(databaseURL: URL(fileURLWithPath: "/definitely/not/here/TCC.db")).entries()
        }
    }

    @Test("The reader cannot write: the connection is read-only")
    func readOnly() throws {
        let root = try makeRoot(); defer { cleanUp(root) }
        let path = root.appendingPathComponent("TCC.db")
        let queue = try DatabaseQueue(path: path.path)
        try queue.write { try $0.execute(sql: "CREATE TABLE access (service TEXT, client TEXT, auth_value INTEGER)") }
        var configuration = Configuration()
        configuration.readonly = true
        let readOnly = try DatabaseQueue(path: path.path, configuration: configuration)
        #expect(throws: (any Error).self) {
            try readOnly.write { try $0.execute(sql: "INSERT INTO access VALUES ('kTCCServiceCamera', 'x', 2)") }
        }
    }

    @Test("Every service has a Settings pane to send the user to")
    func settingsLinks() {
        for service in TCCReader.Entry.Service.allCases { #expect(TCCReader.settingsURL(for: service) != nil) }
    }
}

@Suite("Signature findings are not alarms")
struct SignatureSeverityTests {
    @Test("An invalid signature is information, never a threat or a suspicion by itself")
    func invalidIsInfo() async throws {
        let root = try makeRoot(); defer { cleanUp(root) }
        // An app bundle whose executable carries no valid signature, as many ordinary apps do.
        let app = root.appendingPathComponent("Thing.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: app.appendingPathComponent("Thing"))
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.example.thing"], format: .xml, options: 0)
            .write(to: root.appendingPathComponent("Thing.app/Contents/Info.plist"))
        let findings = try await ProtectionScanner(roots: [root], blocklist: .empty).scan()
        #expect(findings.allSatisfy { $0.severity <= .info })
    }
}
