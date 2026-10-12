import Testing
import Foundation
import CoreKit
import ScanEngine
import SafetyKit
@testable import Files

@Suite("Large files model", .serialized)
@MainActor
struct LargeFilesModelTests {
    private func withTree(_ body: (URL, LargeFilesModel) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("BurnishFilesModel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            // Fixture teardown, not product code.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: root)
        }
        let model = LargeFilesModel(roots: [root], minimumSize: ByteCount(1_000_000))
        try await body(root, model)
    }

    private func write(_ name: String, bytes: Int, in root: URL, daysOld: Double = 0) throws {
        let url = root.appendingPathComponent(name)
        try Data(repeating: 0x43, count: bytes).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-daysOld * 86_400)], ofItemAtPath: url.path
        )
    }

    private func scan(_ model: LargeFilesModel) async {
        model.scan()
        await model.session?.waitUntilFinished()
    }

    @Test("Nothing is selected after a scan")
    func nothingSelected() async throws {
        try await withTree { root, model in
            try write("big.mov", bytes: 2_000_000, in: root)
            await scan(model)
            #expect(model.visibleItems.count == 1)
            #expect(model.selection.isEmpty)
            #expect(model.selectedItems.isEmpty)
        }
    }

    @Test("Nothing to approve without a selection")
    func noPlanWithoutSelection() async throws {
        try await withTree { root, model in
            try write("big.mov", bytes: 2_000_000, in: root)
            await scan(model)
            model.prepareConfirmation()
            #expect(model.pendingPlan == nil)
        }
    }

    @Test("The plan holds only what was selected, and goes to the Trash")
    func planIsReversible() async throws {
        try await withTree { root, model in
            try write("a.mov", bytes: 2_000_000, in: root)
            try write("b.mov", bytes: 3_000_000, in: root)
            await scan(model)
            let chosen = try #require(model.visibleItems.first { $0.displayName == "a.mov" })
            model.toggle(chosen)
            model.prepareConfirmation()

            let plan = try #require(model.pendingPlan)
            #expect(plan.items.map(\.displayName) == ["a.mov"])
            #expect(plan.mode == .trash)
            #expect(!plan.mode.isIrreversible)
        }
    }

    @Test("A plan that is not the pending one is ignored")
    func foreignPlanIgnored() async throws {
        try await withTree { root, model in
            try write("a.mov", bytes: 2_000_000, in: root)
            await scan(model)
            model.toggle(try #require(model.visibleItems.first))
            model.prepareConfirmation()
            let plan = try #require(model.pendingPlan)
            model.dismissConfirmation()
            model.confirm(plan)
            if case .deleting = model.phase { Issue.record("must not start deleting") }
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("a.mov").path))
        }
    }

    @Test("The type filter narrows the list")
    func kindFilter() async throws {
        try await withTree { root, model in
            try write("a.mov", bytes: 2_000_000, in: root)
            try write("b.zip", bytes: 2_000_000, in: root)
            await scan(model)
            model.kindFilter = .archive
            #expect(model.visibleItems.map(\.displayName) == ["b.zip"])
        }
    }

    @Test("The age filter keeps only old files")
    func ageFilter() async throws {
        try await withTree { root, model in
            try write("old.mov", bytes: 2_000_000, in: root, daysOld: 400)
            try write("new.mov", bytes: 2_000_000, in: root, daysOld: 2)
            await scan(model)
            model.ageFilter = .overOneYear
            #expect(model.visibleItems.map(\.displayName) == ["old.mov"])
        }
    }

    @Test("Reset returns to idle")
    func resetGoesIdle() async throws {
        try await withTree { root, model in
            try write("a.mov", bytes: 2_000_000, in: root)
            await scan(model)
            model.reset()
            if case .idle = model.phase {} else { Issue.record("expected idle") }
        }
    }
}
