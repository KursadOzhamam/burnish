import Testing
import Foundation
import CoreKit
import ScanEngine
import SafetyKit
import SafetyKitMac
@testable import Applications

@Suite("Applications model", .serialized)
@MainActor
struct ApplicationsModelTests {
    private func withMac(running: Set<String> = [], _ body: (URL, ApplicationsModel) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishAppModel-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        let applications = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Caches/com.example.alpha"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        defer {
            // Fixture teardown, not product code.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: root)
        }
        try Data(repeating: 1, count: 5_000).write(to: home.appendingPathComponent("Library/Caches/com.example.alpha/x.bin"))
        for (name, id, age) in [("Alpha", "com.example.alpha", 0.0), ("Beta", "com.example.beta", 0.0), ("Notes", "com.apple.Notes", 0.0)] {
            let app = applications.appendingPathComponent("\(name).app/Contents")
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
            let info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": name]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Info.plist"))
            _ = age
        }
        let model = ApplicationsModel(
            catalogue: AppCatalogue(roots: [applications]), home: home,
            inspector: StaticRunningApplicationInspector(running)
        )
        await model.load()
        try await body(root, model)
    }

    @Test("Apple apps are hidden unless asked for")
    func appleHidden() async throws {
        try await withMac { _, model in
            #expect(model.visibleApps.map(\.name) == ["Alpha", "Beta"])
            model.includeApple = true
            #expect(model.visibleApps.count == 3)
        }
    }

    @Test("Search narrows the list")
    func search() async throws {
        try await withMac { _, model in
            model.searchText = "alp"
            #expect(model.visibleApps.map(\.name) == ["Alpha"])
        }
    }

    @Test("Apps with no recorded use are not called unused")
    func unusedNeedsEvidence() async throws {
        try await withMac { _, model in
            model.unusedForDays = 30
            // Fake apps have no Spotlight record, so none can be called unused.
            #expect(model.visibleApps.isEmpty)
        }
    }

    @Test("Reviewing an app finds its leftovers and ticks the app and the sure ones")
    func reviewPreselects() async throws {
        try await withMac { _, model in
            let alpha = try #require(model.visibleApps.first { $0.name == "Alpha" })
            await model.review(alpha)
            let plan = try #require(model.plan)
            #expect(plan.leftovers.count == 1)
            #expect(model.selectedItems.count == 2)
        }
    }

    @Test("A running app cannot be selected for removal")
    func runningBlocked() async throws {
        try await withMac(running: ["com.example.alpha"]) { _, model in
            let alpha = try #require(model.visibleApps.first { $0.name == "Alpha" })
            await model.review(alpha)
            #expect(model.plan?.app.blockedReason == .ownerRunning)
            #expect(model.selectedItems.isEmpty)
            model.toggle(try #require(model.plan?.app))
            #expect(model.selectedItems.isEmpty)
        }
    }

    @Test("The removal plan goes to the Trash and holds only the selected items")
    func planIsReversible() async throws {
        try await withMac { _, model in
            let alpha = try #require(model.visibleApps.first { $0.name == "Alpha" })
            await model.review(alpha)
            let leftover = try #require(model.plan?.leftovers.first)
            model.toggle(leftover)
            model.prepareUninstall()
            let plan = try #require(model.pendingPlan)
            #expect(plan.mode == .trash)
            #expect(plan.items.map(\.displayName) == ["Alpha"])
        }
    }

    @Test("Closing the review clears the selection")
    func closing() async throws {
        try await withMac { _, model in
            await model.review(try #require(model.visibleApps.first))
            model.closeReview()
            #expect(model.plan == nil)
            #expect(model.selection.isEmpty)
        }
    }

    @Test("Orphan scan reports gone apps and nothing is preselected")
    func orphans() async throws {
        try await withMac { root, model in
            let folder = root.appendingPathComponent("home/Library/Caches/com.gone.app")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 5_000).write(to: folder.appendingPathComponent("x.bin"))
            await model.scanOrphans()
            #expect(model.orphans.map { $0.url.lastPathComponent } == ["com.gone.app"])
            #expect(model.orphanSelection.isEmpty)
        }
    }
}

@Suite("Reset, extensions and update source", .serialized)
@MainActor
struct ResetAndExtensionTests {
    @Test("Reset keeps the app unticked and ticks only the sure leftovers")
    func resetOnly() async throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishReset-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        let apps = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Caches/com.example.alpha"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Application Support/Alpha"), withIntermediateDirectories: true)
        let contents = apps.appendingPathComponent("Alpha.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.example.alpha", "CFBundleName": "Alpha"], format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try Data(repeating: 1, count: 5_000).write(to: home.appendingPathComponent("Library/Caches/com.example.alpha/x.bin"))
        try Data(repeating: 1, count: 5_000).write(to: home.appendingPathComponent("Library/Application Support/Alpha/y.bin"))
        defer {
            // Fixture teardown, not product code.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: root)
        }
        let model = ApplicationsModel(catalogue: AppCatalogue(roots: [apps]), home: home, inspector: StaticRunningApplicationInspector([]))
        await model.load()
        await model.review(try #require(model.apps.first))
        #expect(model.selectedItems.count == 2, "app + the bundle-id cache")
        model.resetOnly()
        let plan = try #require(model.plan)
        #expect(!model.selection.contains(plan.app.id), "the application itself stays")
        #expect(model.selectedItems.map { $0.url.lastPathComponent } == ["com.example.alpha"])
    }

    @Test("Extensions are listed at low confidence and nothing is preselected")
    func extensions() async throws {
        let home = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishExt-\(UUID().uuidString)")
        let plugin = home.appendingPathComponent("Library/QuickLook/Thing.qlgenerator")
        try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 5_000).write(to: plugin.appendingPathComponent("x"))
        defer {
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: home)
        }
        let model = ApplicationsModel(home: home, inspector: StaticRunningApplicationInspector([]))
        await model.scanExtensions()
        #expect(model.extensions.map { $0.url.lastPathComponent } == ["Thing.qlgenerator"])
        #expect(model.extensions.allSatisfy { $0.confidence == .low })
        #expect(model.extensionSelection.isEmpty)
    }

    @Test("A bundle with an App Store receipt, or with Sparkle, is recognised without any network")
    func updateSource() throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishUpd-\(UUID().uuidString)")
        defer {
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: root)
        }
        let store = root.appendingPathComponent("Store.app")
        try FileManager.default.createDirectory(at: store.appendingPathComponent("Contents/_MASReceipt"), withIntermediateDirectories: true)
        let sparkle = root.appendingPathComponent("Spark.app")
        try FileManager.default.createDirectory(at: sparkle.appendingPathComponent("Contents/Frameworks/Sparkle.framework"), withIntermediateDirectories: true)
        #expect(AppCatalogue.updateSource(of: store, info: [:]) == .appStore)
        #expect(AppCatalogue.updateSource(of: sparkle, info: [:]) == .sparkle)
        #expect(AppCatalogue.updateSource(of: root, info: ["SUFeedURL": "https://x"]) == .sparkle)
        #expect(AppCatalogue.updateSource(of: root, info: [:]) == .unknown)
    }
}
