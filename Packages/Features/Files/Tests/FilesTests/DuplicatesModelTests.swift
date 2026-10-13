import Testing
import Foundation
import CoreKit
import ScanEngine
import SafetyKit
@testable import Files

@Suite("Duplicates model", .serialized)
@MainActor
struct DuplicatesModelTests {
    private func withTree(_ body: (URL, DuplicatesModel) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishDupModel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("deep/er"), withIntermediateDirectories: true)
        defer {
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: root)
        }
        let same = Data(repeating: 9, count: 5_000)
        let old = root.appendingPathComponent("deep/er/old-copy.bin")
        try same.write(to: old)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-86_400 * 200)], ofItemAtPath: old.path)
        try same.write(to: root.appendingPathComponent("a.bin"))
        try same.write(to: root.appendingPathComponent("mid.bin"))
        let model = DuplicatesModel(roots: [root], minimumSize: ByteCount(1_000))
        model.scan()
        await model.session?.waitUntilFinished()
        try await body(root, model)
    }

    @Test("Nothing is selected after a scan")
    func nothingSelected() async throws {
        try await withTree { _, model in
            #expect(model.groups.count == 1)
            #expect(model.selection.isEmpty)
        }
    }

    @Test("The last unselected copy of a group cannot be selected")
    func lastCopyProtected() async throws {
        try await withTree { _, model in
            let group = try #require(model.groups.first)
            let copies = group.children
            #expect(copies.count == 3)
            #expect(model.toggle(copies[0], in: group))
            #expect(model.toggle(copies[1], in: group))
            let refused = model.toggle(copies[2], in: group)
            #expect(refused == false, "selecting the third would delete every copy")
            #expect(model.selection.count == 2)
        }
    }

    @Test("Deselecting is always allowed")
    func deselectAllowed() async throws {
        try await withTree { _, model in
            let group = try #require(model.groups.first)
            model.toggle(group.children[0], in: group)
            #expect(model.toggle(group.children[0], in: group))
            #expect(model.selection.isEmpty)
        }
    }

    @Test("Keep-oldest selects every copy except the oldest")
    func keepOldest() async throws {
        try await withTree { _, model in
            model.apply(.oldest)
            let group = try #require(model.groups.first)
            let kept = group.children.filter { !model.isSelected($0) }
            #expect(kept.map { $0.url.lastPathComponent } == ["old-copy.bin"])
            #expect(model.selection.count == 2)
        }
    }

    @Test("Keep-shortest-path keeps the copy with the shortest path")
    func keepShortest() async throws {
        try await withTree { _, model in
            model.apply(.shortestPath)
            let group = try #require(model.groups.first)
            let kept = try #require(group.children.first { !model.isSelected($0) })
            #expect(kept.url.lastPathComponent == "a.bin")
        }
    }

    @Test("Every rule leaves one copy per group")
    func rulesKeepOne() async throws {
        try await withTree { _, model in
            for rule in DuplicatesModel.KeepRule.allCases {
                model.apply(rule)
                for group in model.groups {
                    #expect(group.children.contains { !model.isSelected($0) })
                }
            }
        }
    }

    @Test("Selected size is what would be freed; reclaimable is the most that could be")
    func sizes() async throws {
        try await withTree { _, model in
            model.apply(.oldest)
            #expect(model.selectedSize == model.reclaimableSize)
            model.clearSelection()
            #expect(model.selectedSize == .zero)
        }
    }

    @Test("The plan holds only the selected copies and goes to the Trash")
    func planIsReversible() async throws {
        try await withTree { _, model in
            model.apply(.oldest)
            model.prepareConfirmation()
            let plan = try #require(model.pendingPlan)
            #expect(plan.mode == .trash)
            #expect(plan.items.count == 2)
            #expect(!plan.items.contains { $0.url.lastPathComponent == "old-copy.bin" })
        }
    }

    @Test("Nothing to approve without a selection")
    func noPlanWithoutSelection() async throws {
        try await withTree { _, model in
            model.prepareConfirmation()
            #expect(model.pendingPlan == nil)
        }
    }
}
