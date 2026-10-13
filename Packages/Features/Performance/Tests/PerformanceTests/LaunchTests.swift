import Testing
import Foundation
import CoreKitMac
@testable import Performance

/// Records what it was asked to run, and answers from a script.
private final class RecordingRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    var output = ""
    var status: Int32 = 0

    var calls: [[String]] { lock.withLock { recorded } }

    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        lock.withLock { recorded.append([executable] + arguments) }
        return CommandResult(status: status, output: output)
    }
}

private func item(_ label: String, scope: LaunchItem.Scope = .userAgent) -> LaunchItem {
    LaunchItem(label: label, plistURL: URL(fileURLWithPath: "/tmp/\(label).plist"), scope: scope, program: nil, runsAtLoad: true, keepsAlive: false)
}

@Suite("Launch items")
struct LaunchItemTests {
    private func withFolders(_ body: (URL) throws -> Void) throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishLaunch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("home/Library/LaunchAgents"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("global"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("daemons"), withIntermediateDirectories: true)
        defer {
            // Fixture teardown, not product code.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: root)
        }
        try body(root)
    }

    private func write(_ plist: [String: Any], to url: URL) throws {
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
    }

    @Test("Jobs are read from all three folders with their scope")
    func readsAll() throws {
        try withFolders { root in
            let agents = root.appendingPathComponent("home/Library/LaunchAgents")
            try write(["Label": "com.example.user", "ProgramArguments": ["/bin/ls"], "RunAtLoad": true], to: agents.appendingPathComponent("a.plist"))
            try write(["Label": "com.example.global", "Program": "/bin/ls"], to: root.appendingPathComponent("global/b.plist"))
            try write(["Label": "com.example.daemon", "KeepAlive": true], to: root.appendingPathComponent("daemons/c.plist"))
            let items = LaunchItemCatalogue(
                home: root.appendingPathComponent("home"), globalAgents: root.appendingPathComponent("global"), daemons: root.appendingPathComponent("daemons")
            ).items()
            #expect(Set(items.map(\.label)) == ["com.example.user", "com.example.global", "com.example.daemon"])
            #expect(items.first { $0.label == "com.example.daemon" }?.scope == .daemon)
            #expect(items.first { $0.label == "com.example.daemon" }?.keepsAlive == true)
            #expect(items.first { $0.label == "com.example.user" }?.runsAtLoad == true)
        }
    }

    @Test("A job whose program is gone is flagged")
    func missingProgram() throws {
        try withFolders { root in
            let agents = root.appendingPathComponent("home/Library/LaunchAgents")
            try write(["Label": "com.example.gone", "ProgramArguments": ["/definitely/not/here"]], to: agents.appendingPathComponent("a.plist"))
            let item = try #require(LaunchItemCatalogue(home: root.appendingPathComponent("home"), globalAgents: root, daemons: root).items().first)
            #expect(item.isProgramMissing)
        }
    }

    @Test("A broken plist is skipped, not fatal")
    func brokenSkipped() throws {
        try withFolders { root in
            try Data("nope".utf8).write(to: root.appendingPathComponent("home/Library/LaunchAgents/bad.plist"))
            #expect(LaunchItemCatalogue(home: root.appendingPathComponent("home"), globalAgents: root, daemons: root).items().isEmpty)
        }
    }

    @Test("Apple jobs and daemons cannot be switched off by the user path")
    func permissions() {
        #expect(!item("com.apple.thing").canBeDisabledByUser)
        #expect(!item("com.example.d", scope: .daemon).canBeDisabledByUser)
        #expect(item("com.example.a").canBeDisabledByUser)
        #expect(item("com.example.g", scope: .globalAgent).canBeDisabledByUser)
    }
}

@Suite("Launch control")
struct LaunchControlTests {
    @Test("Labels with anything but letters, digits and . - _ are refused")
    func labelValidation() {
        #expect(LaunchControl.isValid(label: "com.example.agent-1_x"))
        for bad in ["", "a b", "a;b", "a/b", "a$(x)", "-flag", "a\"b", "a\nb", "é.com"] {
            #expect(!LaunchControl.isValid(label: bad), "\(bad)")
        }
    }

    @Test("Disabling runs launchctl disable and then bootout for the right target, nothing else")
    func disableCommands() async throws {
        let runner = RecordingRunner()
        try await LaunchControl(runner: runner, userID: 501).disable(item("com.example.agent"))
        #expect(runner.calls == [
            ["/bin/launchctl", "disable", "gui/501/com.example.agent"],
            ["/bin/launchctl", "bootout", "gui/501/com.example.agent"]
        ])
    }

    @Test("Enabling runs only launchctl enable")
    func enableCommand() async throws {
        let runner = RecordingRunner()
        try await LaunchControl(runner: runner, userID: 501).enable(item("com.example.agent"))
        #expect(runner.calls == [["/bin/launchctl", "enable", "gui/501/com.example.agent"]])
    }

    @Test("An Apple job, a daemon or a bad label never reaches a command line")
    func refused() async {
        let runner = RecordingRunner()
        let control = LaunchControl(runner: runner, userID: 501)
        await #expect(throws: LaunchControl.ControlError.notAllowed) { try await control.disable(item("com.apple.x")) }
        await #expect(throws: LaunchControl.ControlError.notAllowed) { try await control.disable(item("com.example.d", scope: .daemon)) }
        await #expect(throws: LaunchControl.ControlError.invalidLabel) { try await control.disable(item("bad label")) }
        #expect(runner.calls.isEmpty)
    }

    @Test("A failing disable is reported, and bootout is not attempted")
    func failure() async {
        let runner = RecordingRunner()
        runner.status = 1
        runner.output = "denied"
        await #expect(throws: LaunchControl.ControlError.failed("denied")) {
            try await LaunchControl(runner: runner, userID: 501).disable(item("com.example.agent"))
        }
        #expect(runner.calls.count == 1)
    }

    @Test("print-disabled output is parsed into labels")
    func parsesDisabled() async throws {
        let runner = RecordingRunner()
        runner.output = """
        disabled services = {
            "com.example.off" => disabled
            "com.example.on" => enabled
        }
        """
        let labels = try await LaunchControl(runner: runner, userID: 501).disabledLabels()
        #expect(labels == ["com.example.off"])
    }
}
