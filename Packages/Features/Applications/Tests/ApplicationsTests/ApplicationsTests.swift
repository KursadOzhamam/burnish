import Testing
import Foundation
import CoreKit
import ScanEngine
@testable import Applications

/// A throw-away Mac: a home folder with a Library, and an Applications folder with fake apps.
private struct FakeMac {
    let root: URL
    var home: URL { root.appendingPathComponent("home") }
    var applications: URL { root.appendingPathComponent("Applications") }
    var library: URL { home.appendingPathComponent("Library") }

    init() throws {
        root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishApps-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
    }

    func tearDown() {
        // Fixture teardown, not product code.
        // swiftlint:disable:next no_direct_remove_item
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func app(_ name: String, id: String, in folder: URL? = nil) throws -> URL {
        let url = (folder ?? applications).appendingPathComponent("\(name).app")
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": name, "CFBundleShortVersionString": "1.2"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try Data(repeating: 1, count: 20_000).write(to: contents.appendingPathComponent("MacOS/\(name)"))
        return url
    }

    @discardableResult
    func library(_ path: String, bytes: Int = 5_000) throws -> URL {
        let url = library.appendingPathComponent(path)
        if path.hasSuffix(".plist") || path.hasSuffix(".savedState") == false && !path.contains("/") == false {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 2, count: bytes).write(to: url)
        return url
    }
}

@Suite("Installed apps", .serialized)
struct AppCatalogueTests {
    @Test("Apps are found with their name, identifier and version")
    func finds() throws {
        let mac = try FakeMac(); defer { mac.tearDown() }
        try mac.app("Alpha", id: "com.example.alpha")
        let apps = try AppCatalogue(roots: [mac.applications]).installedApps()
        let alpha = try #require(apps.first)
        #expect(alpha.name == "Alpha")
        #expect(alpha.bundleID == "com.example.alpha")
        #expect(alpha.version == "1.2")
        #expect(alpha.size.bytes > 0)
    }

    @Test("An app inside a vendor folder is found, a deeper one is not")
    func depth() throws {
        let mac = try FakeMac(); defer { mac.tearDown() }
        let vendor = mac.applications.appendingPathComponent("Vendor")
        try FileManager.default.createDirectory(at: vendor, withIntermediateDirectories: true)
        try mac.app("Inner", id: "com.example.inner", in: vendor)
        let deep = vendor.appendingPathComponent("a/b/c")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try mac.app("TooDeep", id: "com.example.deep", in: deep)
        let names = try AppCatalogue(roots: [mac.applications]).installedApps().map(\.name)
        #expect(names == ["Inner"])
    }

    @Test("Apple's own apps are marked, and results are sorted by name")
    func appleAndOrder() throws {
        let mac = try FakeMac(); defer { mac.tearDown() }
        try mac.app("Zed", id: "com.example.zed")
        try mac.app("Notes", id: "com.apple.Notes")
        let apps = try AppCatalogue(roots: [mac.applications]).installedApps()
        #expect(apps.map(\.name) == ["Notes", "Zed"])
        #expect(apps[0].isApple)
        #expect(!apps[1].isApple)
    }
}

@Suite("Leftovers", .serialized)
struct LeftoverFinderTests {
    private func app(_ id: String, _ name: String) -> InstalledApp {
        InstalledApp(url: URL(fileURLWithPath: "/Applications/\(name).app"), name: name, bundleID: id, version: nil, size: .zero, lastUsed: nil)
    }

    @Test("Folders and files named with the bundle identifier are found at medium confidence")
    func byBundleID() throws {
        let mac = try FakeMac(); defer { mac.tearDown() }
        try mac.library("Application Support/com.example.alpha/data.bin")
        try mac.library("Caches/com.example.alpha/cache.bin")
        try mac.library("Preferences/com.example.alpha.plist")
        try mac.library("Saved Application State/com.example.alpha.savedState/state.bin")
        let found = try LeftoverFinder(home: mac.home).leftovers(of: app("com.example.alpha", "Alpha"))
        #expect(found.count == 4)
        #expect(found.allSatisfy { $0.confidence == .medium })
    }

    @Test("A folder named only after the app is low confidence")
    func byNameOnly() throws {
        let mac = try FakeMac(); defer { mac.tearDown() }
        try mac.library("Application Support/Alpha Studio/data.bin")
        let found = try LeftoverFinder(home: mac.home).leftovers(of: app("com.example.alphastudio", "Alpha Studio"))
        #expect(found.count == 1)
        #expect(found[0].confidence == .low)
    }

    @Test("A sibling application's data is not taken")
    func siblingNotTaken() throws {
        let mac = try FakeMac(); defer { mac.tearDown() }
        try mac.library("Application Support/com.example.app.canary/data.bin")
        try mac.library("Application Support/com.example.app/data.bin")
        let found = try LeftoverFinder(home: mac.home).leftovers(
            of: app("com.example.app", "App"), otherBundleIDs: ["com.example.app.canary"]
        )
        #expect(found.map { $0.url.lastPathComponent } == ["com.example.app"])
    }

    @Test("A helper of the same app is taken: bundle identifier plus a suffix")
    func helperTaken() throws {
        let mac = try FakeMac(); defer { mac.tearDown() }
        try mac.library("Caches/com.example.app.ShipIt/x.bin")
        let found = try LeftoverFinder(home: mac.home).leftovers(of: app("com.example.app", "App"))
        #expect(found.count == 1)
    }

    @Test("Group containers carrying the identifier are found")
    func groupContainer() throws {
        let mac = try FakeMac(); defer { mac.tearDown() }
        try mac.library("Group Containers/ABCDE12345.com.example.app/data.bin")
        let found = try LeftoverFinder(home: mac.home).leftovers(of: app("com.example.app", "App"))
        #expect(found.count == 1)
    }

    @Test("Something unrelated is left alone, and so is a name that is too short to trust")
    func unrelatedIgnored() throws {
        let mac = try FakeMac(); defer { mac.tearDown() }
        try mac.library("Application Support/Other/data.bin")
        try mac.library("Application Support/Go/data.bin")
        let found = try LeftoverFinder(home: mac.home).leftovers(of: app("com.example.go", "Go"))
        #expect(found.isEmpty)
    }

    @Test("Matching is not by substring: the identifier of a longer name does not match")
    func noSubstring() throws {
        let mac = try FakeMac(); defer { mac.tearDown() }
        try mac.library("Caches/com.example.application/x.bin")
        let found = try LeftoverFinder(home: mac.home).leftovers(of: app("com.example.app", "App"))
        #expect(found.isEmpty)
    }
}

@Suite("Orphans", .serialized)
struct OrphanFinderTests {
    private func installedApp(_ id: String) -> InstalledApp {
        InstalledApp(url: URL(fileURLWithPath: "/Applications/X.app"), name: "X", bundleID: id, version: nil, size: .zero, lastUsed: nil)
    }

    @Test("A bundle-id-like folder with no installed app is reported, at low confidence")
    func orphanFound() throws {
        let mac = try FakeMac(); defer { mac.tearDown() }
        try mac.library("Application Support/com.gone.app/data.bin")
        let found = try OrphanFinder(home: mac.home).orphans(installed: [])
        #expect(found.count == 1)
        #expect(found[0].confidence == .low)
    }

    @Test("An installed app's data, and its helpers, are not orphans")
    func installedNotOrphan() throws {
        let mac = try FakeMac(); defer { mac.tearDown() }
        try mac.library("Application Support/com.here.app/data.bin")
        try mac.library("Caches/com.here.app.helper/x.bin")
        #expect(try OrphanFinder(home: mac.home).orphans(installed: [installedApp("com.here.app")]).isEmpty)
    }

    @Test("Apple identifiers are never reported")
    func appleSkipped() throws {
        let mac = try FakeMac(); defer { mac.tearDown() }
        try mac.library("Caches/com.apple.thing/x.bin")
        try mac.library("Preferences/com.apple.other.plist")
        #expect(try OrphanFinder(home: mac.home).orphans(installed: []).isEmpty)
    }

    @Test("A running app's folder is not an orphan")
    func runningNotOrphan() throws {
        let mac = try FakeMac(); defer { mac.tearDown() }
        try mac.library("Caches/com.live.tool/x.bin")
        #expect(try OrphanFinder(home: mac.home).orphans(installed: [], running: ["com.live.tool"]).isEmpty)
    }

    @Test("A vendor with an app installed shares components, so its other folders are not orphans")
    func sameVendorNotOrphan() throws {
        let mac = try FakeMac(); defer { mac.tearDown() }
        try mac.library("Application Support/com.vendor.shared/data.bin")
        let found = try OrphanFinder(home: mac.home).orphans(installed: [installedApp("com.vendor.main")])
        #expect(found.isEmpty)
    }

    @Test("Developer tooling folders are not reported")
    func toolingSkipped() throws {
        let mac = try FakeMac(); defer { mac.tearDown() }
        try mac.library("Caches/org.swift.swiftpm/x.bin")
        #expect(try OrphanFinder(home: mac.home).orphans(installed: []).isEmpty)
    }

    @Test("Plain names that are not identifiers are ignored")
    func plainNamesIgnored() {
        #expect(!OrphanFinder.looksLikeBundleID("Google"))
        #expect(!OrphanFinder.looksLikeBundleID("My Folder.v2.x"))
        #expect(OrphanFinder.looksLikeBundleID("com.vendor.product"))
        #expect(OrphanFinder.looksLikeBundleID("com.vendor.product.plist"))
    }
}

@Suite("Uninstall plan")
struct UninstallPlanTests {
    private func app(_ id: String) -> InstalledApp {
        InstalledApp(url: URL(fileURLWithPath: "/Applications/A.app"), name: "A", bundleID: id, version: nil, size: ByteCount(100), lastUsed: nil)
    }

    private func leftover(_ name: String, _ confidence: ScanItem.Confidence) -> ScanItem {
        ScanItem(scanner: LeftoverFinder.scannerID, url: URL(fileURLWithPath: "/lib/\(name)"), size: ByteCount(10), confidence: confidence)
    }

    @Test("The app and medium leftovers are ticked; name-only matches are not")
    func preselection() {
        let plan = UninstallPlan(app: app("com.example.a"), leftovers: [leftover("sure", .medium), leftover("maybe", .low)], running: [])
        #expect(plan.preselected.map(\.displayName).sorted() == ["A", "sure"])
    }

    @Test("A running app is blocked, together with its leftovers")
    func runningBlocks() {
        let plan = UninstallPlan(app: app("com.example.a"), leftovers: [leftover("x", .medium)], running: ["com.example.a"])
        #expect(plan.app.blockedReason == .ownerRunning)
        #expect(plan.leftovers.allSatisfy { $0.blockedReason == .ownerRunning })
        #expect(plan.preselected.isEmpty)
    }

    @Test("An Apple app is protected")
    func appleProtected() {
        let plan = UninstallPlan(app: app("com.apple.Notes"), leftovers: [], running: [])
        #expect(plan.app.blockedReason == .protectedPath)
    }
}
