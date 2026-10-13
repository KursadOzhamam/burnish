import Testing
import Foundation
@testable import Performance

@Suite("Process sampler")
struct ProcessSamplerTests {
    @Test("The current process is in the table, with memory")
    func seesItself() {
        let samples = ProcessSampler().sample()
        let me = samples.first { $0.pid == getpid() }
        #expect(me != nil)
        #expect((me?.residentBytes ?? 0) > 0)
        #expect(me?.isSystem == false)
    }

    @Test("A busy loop shows as CPU load over a short interval")
    func measuresLoad() async {
        let busy = Task.detached {
            let end = Date().addingTimeInterval(1.2)
            var x = 0.0
            while Date() < end { x += 1 }
            return x
        }
        let loads = await ProcessSampler().load(over: 0.8)
        _ = await busy.value
        let mine = loads.first { $0.sample.pid == getpid() }
        #expect((mine?.cpuPercent ?? 0) > 20, "a spinning thread uses a good part of a core")
    }

    @Test("Root's processes and system folders count as system")
    func systemDetection() {
        let root = ProcessSample(pid: 1, name: "launchd", path: "/sbin/launchd", userID: 0, residentBytes: 1, cpuTimeNanoseconds: 0)
        let system = ProcessSample(pid: 2, name: "x", path: "/System/Library/x", userID: 501, residentBytes: 1, cpuTimeNanoseconds: 0)
        let user = ProcessSample(pid: 3, name: "app", path: "/Applications/App.app/x", userID: 501, residentBytes: 1, cpuTimeNanoseconds: 0)
        #expect(root.isSystem)
        #expect(system.isSystem)
        #expect(!user.isSystem)
    }

    @Test("Top lists are ordered and limited")
    func topLists() {
        let samples = (1...5).map {
            ProcessSample(pid: Int32($0), name: "p\($0)", path: nil, userID: 501, residentBytes: UInt64($0) * 10, cpuTimeNanoseconds: 0)
        }
        #expect(ProcessSampler.topByMemory(samples, count: 2).map(\.pid) == [5, 4])
    }
}

@Suite("Maintenance tasks")
struct MaintenanceTaskTests {
    @Test("Every task maps to an absolute executable and fixed arguments")
    func commandsAreFixed() {
        for task in MaintenanceTask.allCases {
            #expect(task.command.executable.hasPrefix("/"), "\(task)")
            #expect(!task.command.arguments.contains { $0.contains(" ") || $0.contains(";") || $0.contains("$") })
        }
    }

    @Test("Only the Launch Services rebuild runs without the helper")
    func helperRequirement() {
        #expect(MaintenanceTask.allCases.filter { !$0.requiresHelper } == [.rebuildLaunchServices])
    }

    @Test("The exact commands are the ones the spec describes")
    func exactCommands() {
        #expect(MaintenanceTask.flushDNS.command.executable == "/usr/bin/dscacheutil")
        #expect(MaintenanceTask.flushDNS.command.arguments == ["-flushcache"])
        #expect(MaintenanceTask.purgeMemory.command.executable == "/usr/sbin/purge")
        #expect(MaintenanceTask.verifyDisk.command.arguments == ["verifyVolume", "/"])
    }
}

@Suite("Burnish footprint")
struct BurnishFootprintTests {
    @Test("Only what exists is listed, and nothing outside Burnish's own names")
    func listsExisting() throws {
        let home = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishFoot-\(UUID().uuidString)")
        let library = home.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: library.appendingPathComponent("Application Support/Burnish"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library.appendingPathComponent("Application Support/Other"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library.appendingPathComponent("Preferences"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: library.appendingPathComponent("Application Support/Burnish/history.sqlite"))
        try Data(repeating: 1, count: 100).write(to: library.appendingPathComponent("Preferences/com.burnish.app.plist"))
        try Data(repeating: 1, count: 100).write(to: library.appendingPathComponent("Preferences/com.other.plist"))
        defer {
            // Fixture teardown, not product code.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: home)
        }
        let items = BurnishFootprint(home: home, bundleIdentifier: "com.burnish.app", supportFolderName: "Burnish").items()
        #expect(items.map { $0.url.lastPathComponent }.sorted() == ["Burnish", "com.burnish.app.plist"])
        #expect(items.allSatisfy { $0.confidence == .medium })
    }

    @Test("A Mac with no Burnish data lists nothing")
    func empty() {
        let home = URL(fileURLWithPath: "/private/tmp/BurnishNoFoot-\(UUID().uuidString)")
        #expect(BurnishFootprint(home: home).items().isEmpty)
    }
}
