import Testing
import Foundation
import CoreKitMac
import HelperProtocol
@testable import Performance

private final class FakeHelper: HelperManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var ran: [HelperCommand] = []
    var current: HelperStatus = .enabled
    var result = CommandResult(status: 0, output: "done")

    var commands: [HelperCommand] { lock.withLock { ran } }
    func status() async -> HelperStatus { current }
    func install() async -> HelperStatus { current = .requiresApproval; return current }
    func openSettings() {}
    func run(_ command: HelperCommand) async throws -> CommandResult {
        lock.withLock { ran.append(command) }
        return result
    }
    func removeSystemItems(_ paths: [String]) async throws -> [String] { [] }
}

private final class FakeRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    var calls: [[String]] { lock.withLock { recorded } }
    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        lock.withLock { recorded.append([executable] + arguments) }
        return CommandResult(status: 0, output: "")
    }
}

@Suite("Performance model")
@MainActor
struct PerformanceModelTests {
    private func model(helper: FakeHelper = FakeHelper(), runner: FakeRunner = FakeRunner()) -> PerformanceModel {
        PerformanceModel(helper: helper, runner: runner, defaults: nil, notify: { _ in }, requestPermission: {})
    }

    @Test("A task that needs root is refused until the helper is enabled")
    func rootNeedsHelper() async {
        let helper = FakeHelper()
        helper.current = .notRegistered
        let model = model(helper: helper)
        await model.refreshHelper()
        #expect(!model.canRun(.flushDNS))
        await model.run(.flushDNS)
        #expect(model.state(of: .flushDNS) == .idle)
        #expect(helper.commands.isEmpty)
    }

    @Test("With the helper enabled, a root task goes to the helper and nothing else")
    func helperRuns() async {
        let helper = FakeHelper()
        let runner = FakeRunner()
        let model = model(helper: helper, runner: runner)
        await model.refreshHelper()
        await model.run(.purgeMemory)
        #expect(helper.commands == [.purgeMemory])
        #expect(runner.calls.isEmpty)
        #expect(model.state(of: .purgeMemory) == .succeeded("done"))
    }

    @Test("The Launch Services rebuild runs locally with its fixed command, never through the helper")
    func localTask() async {
        let helper = FakeHelper()
        let runner = FakeRunner()
        let model = model(helper: helper, runner: runner)
        await model.run(.rebuildLaunchServices)
        #expect(helper.commands.isEmpty)
        #expect(runner.calls.count == 1)
        #expect(runner.calls[0][0].hasSuffix("lsregister"))
    }

    @Test("A failing command is reported with its output")
    func failure() async {
        let helper = FakeHelper()
        helper.result = CommandResult(status: 1, output: "no space left")
        let model = model(helper: helper)
        await model.refreshHelper()
        await model.run(.verifyDisk)
        #expect(model.state(of: .verifyDisk) == .failed("no space left"))
    }

    @Test("Installing moves the helper to waiting for the user's approval")
    func install() async {
        let helper = FakeHelper()
        helper.current = .notRegistered
        let model = model(helper: helper)
        await model.installHelper()
        #expect(model.helperStatus == .requiresApproval)
    }

    @Test("A process of the system, or this app, cannot be asked to quit")
    func quitGuard() {
        let model = model()
        let system = ProcessSample(pid: 1, name: "launchd", path: "/sbin/launchd", userID: 0, residentBytes: 1, cpuTimeNanoseconds: 0)
        let me = ProcessSample(pid: getpid(), name: "me", path: nil, userID: 501, residentBytes: 1, cpuTimeNanoseconds: 0)
        #expect(!model.canQuit(system))
        #expect(!model.canQuit(me))
    }

    @Test("The memory pressure choice is remembered")
    func pressureSetting() throws {
        let name = "BurnishPerfTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let first = PerformanceModel(helper: FakeHelper(), runner: FakeRunner(), defaults: defaults, notify: { _ in }, requestPermission: {})
        #expect(!first.notifiesOnMemoryPressure)
        first.setNotifiesOnMemoryPressure(true)
        first.setNotifiesOnMemoryPressure(false)
        defaults.set(true, forKey: "performance.memoryPressureNotify")
        let second = PerformanceModel(helper: FakeHelper(), runner: FakeRunner(), defaults: defaults, notify: { _ in }, requestPermission: {})
        #expect(second.notifiesOnMemoryPressure)
    }
}
