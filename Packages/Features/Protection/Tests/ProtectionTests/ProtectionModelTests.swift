import Testing
import Foundation
import CoreKitMac
@testable import Protection

private let eicar = "X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*"

private final class StubRunner: CommandRunning, @unchecked Sendable {
    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        CommandResult(status: 0, output: "enabled")
    }
}

@Suite("Protection model", .serialized)
@MainActor
struct ProtectionModelTests {
    private func withModel(_ body: (URL, URL, ProtectionModel) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishProtModel-\(UUID().uuidString)")
        let scanned = root.appendingPathComponent("scanned")
        let support = root.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: scanned, withIntermediateDirectories: true)
        defer {
            // Fixture teardown, not product code.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: root)
        }
        let model = ProtectionModel(
            roots: [scanned], supportDirectory: support,
            persistence: PersistenceAnalyzer(home: root.appendingPathComponent("nohome"), extraFolders: []),
            defense: AppleDefense(runner: StubRunner()),
            tcc: TCCReader(databaseURL: root.appendingPathComponent("none.db"))
        )
        try await body(scanned, support, model)
    }

    private func scan(_ model: ProtectionModel) async throws {
        model.scan()
        for _ in 0..<200 {
            if model.phase == .finished { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("scan did not finish")
    }

    @Test("A scan finds the test file and records when it finished")
    func finds() async throws {
        try await withModel { scanned, _, model in
            try Data(eicar.utf8).write(to: scanned.appendingPathComponent("eicar.sh"))
            try await scan(model)
            #expect(model.findings.count == 1)
            #expect(model.worstSeverity == .threat)
            #expect(model.lastScan != nil)
        }
    }

    @Test("Quarantine moves the file, removes the finding and can be undone")
    func quarantineAndRestore() async throws {
        try await withModel { scanned, _, model in
            let file = scanned.appendingPathComponent("eicar.sh")
            try Data(eicar.utf8).write(to: file)
            try await scan(model)
            model.quarantine(try #require(model.findings.first))
            #expect(!FileManager.default.fileExists(atPath: file.path))
            #expect(model.findings.isEmpty)
            #expect(model.quarantined.count == 1)
            model.restore(try #require(model.quarantined.first))
            #expect(FileManager.default.fileExists(atPath: file.path))
            #expect(model.quarantined.isEmpty)
        }
    }

    @Test("'This is safe' removes the finding now and silences it on the next scan")
    func allowRemembered() async throws {
        try await withModel { scanned, _, model in
            try Data(eicar.utf8).write(to: scanned.appendingPathComponent("eicar.sh"))
            try await scan(model)
            model.allow(try #require(model.findings.first))
            #expect(model.findings.isEmpty)
            try await scan(model)
            #expect(model.findings.isEmpty, "the allow-list survives a rescan")
        }
    }

    @Test("A finding in a protected location cannot be quarantined")
    func protectedRefused() async throws {
        try await withModel { _, _, model in
            let home = FileManager.default.homeDirectoryForCurrentUser
            let protected = Finding(url: home.appendingPathComponent(".ssh/id_rsa"), severity: .suspicious, reason: .invalidSignature)
            model.quarantine(protected)
            #expect(model.message == .refused("id_rsa"))
            #expect(model.quarantined.isEmpty)
        }
    }

    @Test("System status reads Gatekeeper and SIP from the fixed commands")
    func status() async throws {
        try await withModel { _, _, model in
            await model.refreshStatus()
            #expect(model.status?.gatekeeperEnabled == true)
            #expect(model.status?.sipEnabled == true)
        }
    }

    @Test("Unreadable privacy permissions are reported as needing Full Disk Access")
    func permissionsNeedFDA() async throws {
        try await withModel { _, _, model in
            await model.refreshStatus()
            #expect(model.permissionsNeedFullDiskAccess)
            #expect(model.permissions.isEmpty)
        }
    }

    @Test("Cancelling a scan returns to idle")
    func cancelling() async throws {
        try await withModel { _, _, model in
            model.scan()
            model.cancel()
            #expect(model.phase == .idle)
        }
    }
}
