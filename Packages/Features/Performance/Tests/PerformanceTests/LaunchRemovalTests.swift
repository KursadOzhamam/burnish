import Testing
import Foundation
import CoreKitMac
import HelperProtocol
@testable import Performance

private final class Recorder: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    var calls: [[String]] { lock.withLock { recorded } }
    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        lock.withLock { recorded.append([executable] + arguments) }
        return CommandResult(status: 0, output: "")
    }
}

private final class IdleHelper: HelperManaging, @unchecked Sendable {
    func status() async -> HelperStatus { .notRegistered }
    func install() async -> HelperStatus { .notRegistered }
    func openSettings() {}
    func run(_ command: HelperCommand) async throws -> CommandResult { CommandResult(status: 0, output: "") }
    func removeSystemItems(_ paths: [String]) async throws -> [String] { [] }
}

private func job(_ label: String, scope: LaunchItem.Scope, at url: URL? = nil) -> LaunchItem {
    LaunchItem(
        label: label, plistURL: url ?? URL(fileURLWithPath: "/tmp/\(label).plist"), scope: scope,
        program: nil, runsAtLoad: true, keepsAlive: false
    )
}

@Suite("Startup item removal")
struct LaunchRemovalTests {
    @Test("Only the user's own, non-Apple agents can be removed")
    func whoCanBeRemoved() {
        #expect(job("com.example.agent", scope: .userAgent).canBeRemovedByUser)
        #expect(!job("com.apple.something", scope: .userAgent).canBeRemovedByUser)
        #expect(!job("com.example.global", scope: .globalAgent).canBeRemovedByUser)
        #expect(!job("com.example.daemon", scope: .daemon).canBeRemovedByUser)
    }

    @Test("Unloading stops the job in the user's own domain and nowhere else")
    func unloadTarget() async throws {
        let runner = Recorder()
        try await LaunchControl(runner: runner, userID: 501).unload(job("com.example.agent", scope: .userAgent))
        #expect(runner.calls == [["/bin/launchctl", "bootout", "gui/501/com.example.agent"]])
    }

    @Test("Unloading refuses jobs that are not removable and labels that are not plain")
    func unloadRefusals() async {
        let control = LaunchControl(runner: Recorder(), userID: 501)
        await #expect(throws: LaunchControl.ControlError.notAllowed) {
            try await control.unload(job("com.example.global", scope: .globalAgent))
        }
        await #expect(throws: LaunchControl.ControlError.invalidLabel) {
            try await control.unload(job("bad label; rm", scope: .userAgent))
        }
    }

    @Test("The removal plan holds exactly the job's plist, and nothing for a job that cannot be removed")
    @MainActor
    func planIsTheExactPlist() throws {
        let folder = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishRemove-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            // Fixture teardown, not product code.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: folder)
        }
        let plist = folder.appendingPathComponent("com.example.agent.plist")
        try Data("<plist/>".utf8).write(to: plist)

        let model = PerformanceModel(
            helper: IdleHelper(), runner: Recorder(), control: LaunchControl(runner: Recorder(), userID: 501),
            defaults: nil, notify: { _ in }, requestPermission: {}
        )
        model.prepareRemoval(job("com.example.global", scope: .globalAgent, at: plist))
        #expect(model.pendingPlan == nil)

        model.prepareRemoval(job("com.example.agent", scope: .userAgent, at: plist))
        let plan = try #require(model.pendingPlan)
        #expect(plan.items.map(\.url.lastPathComponent) == ["com.example.agent.plist"])
        #expect(!plan.mode.isIrreversible)

        model.dismissRemoval()
        #expect(model.pendingPlan == nil)
        #expect(FileManager.default.fileExists(atPath: plist.path))
    }
}
