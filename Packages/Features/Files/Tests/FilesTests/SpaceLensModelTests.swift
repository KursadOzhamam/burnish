import Testing
import Foundation
import CoreKit
import ScanEngine
import SafetyKit
@testable import Files

@Suite("Space Lens model", .serialized)
@MainActor
struct SpaceLensModelTests {
    private func withTree(_ body: (URL, SpaceLensModel) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishLensModel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a/inner"), withIntermediateDirectories: true)
        defer {
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: root)
        }
        try Data(repeating: 1, count: 3_000_000).write(to: root.appendingPathComponent("a/inner/deep.bin"))
        try Data(repeating: 1, count: 2_000_000).write(to: root.appendingPathComponent("a/shallow.bin"))
        try Data(repeating: 1, count: 5_000_000).write(to: root.appendingPathComponent("top.bin"))
        let model = SpaceLensModel(root: root)
        model.scan()
        await model.session?.waitUntilFinished()
        try await body(root, model)
    }

    @Test("A finished scan puts the root in focus with nothing selected")
    func startsAtRoot() async throws {
        try await withTree { root, model in
            #expect(model.focus?.url == root)
            #expect(model.breadcrumb.count == 1)
            #expect(model.selection.isEmpty)
        }
    }

    @Test("Zooming into a folder extends the breadcrumb, zooming out shortens it")
    func zoomInOut() async throws {
        try await withTree { root, model in
            let a = try #require(model.focus?.children.first { $0.url.lastPathComponent == "a" })
            model.zoom(into: a)
            #expect(model.focus?.url.lastPathComponent == "a")
            #expect(model.breadcrumb.count == 2)
            model.zoomOut()
            #expect(model.focus?.url == root)
        }
    }

    @Test("A file cannot be zoomed into")
    func fileNotZoomable() async throws {
        try await withTree { _, model in
            let top = try #require(model.focus?.children.first { $0.url.lastPathComponent == "top.bin" })
            model.zoom(into: top)
            #expect(model.breadcrumb.count == 1)
        }
    }

    @Test("A breadcrumb level jumps back to that folder")
    func jumpToLevel() async throws {
        try await withTree { root, model in
            let a = try #require(model.focus?.children.first { $0.url.lastPathComponent == "a" })
            model.zoom(into: a)
            let inner = try #require(model.focus?.children.first { $0.url.lastPathComponent == "inner" })
            model.zoom(into: inner)
            #expect(model.breadcrumb.count == 3)
            model.zoom(toLevel: 0)
            #expect(model.focus?.url == root)
        }
    }

    @Test("A selected folder and a file inside it are counted once")
    func nestedSelectionCountedOnce() async throws {
        try await withTree { _, model in
            let a = try #require(model.focus?.children.first { $0.url.lastPathComponent == "a" })
            let shallow = try #require(a.children.first { $0.url.lastPathComponent == "shallow.bin" })
            model.toggle(a)
            model.toggle(shallow)
            #expect(model.selectedSize == a.totalSize)
        }
    }

    @Test("Nothing to approve without a selection; the plan is a reversible Trash plan")
    func planFlow() async throws {
        try await withTree { _, model in
            model.prepareConfirmation()
            #expect(model.pendingPlan == nil)
            let top = try #require(model.focus?.children.first { $0.url.lastPathComponent == "top.bin" })
            model.toggle(top)
            model.prepareConfirmation()
            let plan = try #require(model.pendingPlan)
            #expect(plan.mode == .trash)
            #expect(plan.items.map(\.displayName) == ["top.bin"])
        }
    }

    @Test("An 'other' block can never be selected")
    func otherBlockNotSelectable() async throws {
        try await withTree { _, model in
            let other = ScanItem(scanner: ScannerID("x"), url: URL(fileURLWithPath: "/x"), displayName: "",
                                 size: ByteCount(1), blockedReason: .outsideScope)
            model.toggle(other)
            #expect(model.selection.isEmpty)
        }
    }
}
