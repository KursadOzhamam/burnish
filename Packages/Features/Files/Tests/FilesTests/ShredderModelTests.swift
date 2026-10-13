import Testing
import Foundation
import CoreKit
import ScanEngine
import SafetyKit
@testable import Files

@Suite("Shredder model", .serialized)
@MainActor
struct ShredderModelTests {
    private func withFiles(_ body: (URL) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishShred-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            // Fixture teardown, not product code.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: root)
        }
        try await body(root)
    }

    @discardableResult
    private func file(_ name: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(repeating: 1, count: 10_000).write(to: url)
        return url
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    @Test("Added files are listed with their size and are actionable")
    func addsEntries() async throws {
        try await withFiles { root in
            let model = ShredderModel()
            await model.add([try file("a.bin", in: root)])
            #expect(model.entries.count == 1)
            #expect(model.actionable.count == 1)
            #expect(model.totalSize.bytes > 0)
        }
    }

    @Test("Adding the same file twice lists it once")
    func noDuplicates() async throws {
        try await withFiles { root in
            let model = ShredderModel()
            let url = try file("a.bin", in: root)
            await model.add([url])
            await model.add([url])
            #expect(model.entries.count == 1)
        }
    }

    @Test("A path that does not exist is not added")
    func missingIgnored() async throws {
        try await withFiles { root in
            let model = ShredderModel()
            await model.add([root.appendingPathComponent("ghost.bin")])
            #expect(model.entries.isEmpty)
        }
    }

    @Test("A protected folder is listed but blocked, even though the user picked it")
    func protectedBlocked() async throws {
        let model = ShredderModel()
        let documents = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        await model.add([documents])
        let entry = try #require(model.entries.first)
        #expect(!entry.isActionable)
        #expect(model.actionable.isEmpty)
    }

    @Test("A system path is blocked")
    func systemBlocked() async throws {
        let model = ShredderModel()
        await model.add([URL(fileURLWithPath: "/System/Library")])
        #expect(model.actionable.isEmpty)
    }

    @Test("No plan can be built until the user has acknowledged that it is permanent")
    func needsAcknowledgement() async throws {
        try await withFiles { root in
            let model = ShredderModel()
            await model.add([try file("a.bin", in: root)])
            model.prepareConfirmation()
            #expect(model.pendingPlan == nil)
            model.acknowledgedIrreversible = true
            model.prepareConfirmation()
            #expect(model.pendingPlan != nil)
        }
    }

    @Test("The plan is permanent and needs the extra confirmation")
    func planIsPermanent() async throws {
        try await withFiles { root in
            let model = ShredderModel()
            await model.add([try file("a.bin", in: root)])
            model.acknowledgedIrreversible = true
            model.prepareConfirmation()
            let plan = try #require(model.pendingPlan)
            #expect(plan.mode == .permanent)
            #expect(plan.requiresExtraConfirmation)
        }
    }

    @Test("Nothing is touched while the sheet is open or after it is dismissed")
    func dismissLeavesFiles() async throws {
        try await withFiles { root in
            let url = try file("a.bin", in: root)
            let model = ShredderModel()
            await model.add([url])
            model.acknowledgedIrreversible = true
            model.prepareConfirmation()
            #expect(exists(url))
            model.dismissConfirmation()
            #expect(exists(url))
        }
    }

    @Test("Confirming removes exactly the chosen files and leaves their neighbours")
    func removesOnlyChosen() async throws {
        try await withFiles { root in
            let chosen = try file("chosen.bin", in: root)
            let neighbour = try file("neighbour.bin", in: root)
            let model = ShredderModel()
            await model.add([chosen])
            model.acknowledgedIrreversible = true
            model.prepareConfirmation()
            model.confirm(try #require(model.pendingPlan))

            for _ in 0..<100 {
                if case .finished = model.phase { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            guard case .finished(let report) = model.phase else { Issue.record("did not finish"); return }
            #expect(!exists(chosen))
            #expect(exists(neighbour), "a file the user did not choose must survive")
            #expect(report.mode == .permanent)
        }
    }

    @Test("A plan that is not the pending one is ignored")
    func foreignPlanIgnored() async throws {
        try await withFiles { root in
            let url = try file("a.bin", in: root)
            let model = ShredderModel()
            await model.add([url])
            model.acknowledgedIrreversible = true
            model.prepareConfirmation()
            let plan = try #require(model.pendingPlan)
            model.dismissConfirmation()
            model.confirm(plan)
            try await Task.sleep(for: .milliseconds(100))
            #expect(exists(url))
        }
    }

    @Test("Removing an entry takes it off the list, and clearing resets the acknowledgement")
    func removeAndClear() async throws {
        try await withFiles { root in
            let model = ShredderModel()
            await model.add([try file("a.bin", in: root), try file("b.bin", in: root)])
            model.remove(try #require(model.entries.first))
            #expect(model.entries.count == 1)
            model.acknowledgedIrreversible = true
            model.clear()
            #expect(model.entries.isEmpty)
            #expect(!model.acknowledgedIrreversible)
        }
    }
}
