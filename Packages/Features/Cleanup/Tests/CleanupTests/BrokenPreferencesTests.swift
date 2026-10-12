import Testing
import Foundation
import CoreKit
import ScanEngine
import SafetyKitMac
@testable import Cleanup

/// Only genuinely broken preference files are offered; unreadable and Apple's own never are.
@Suite("Broken preferences", .serialized)
struct BrokenPreferencesTests {

    private func withPreferences(_ body: (URL, URL) async throws -> Void) async throws {
        let home = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("BurnishPrefHome-\(UUID().uuidString)")
        let prefs = home.appendingPathComponent("Library/Preferences")
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        defer {
            // Restore access so teardown can remove it; fixture cleanup, not product code.
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: prefs.appendingPathComponent("locked.plist").path)
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: home)
        }
        try await body(home, prefs)
    }

    private func scan(home: URL) async throws -> [ScanItem] {
        try await CleanupScanner(
            rule: CleanupCatalogue.brokenPreferences,
            home: home,
            inspector: StaticRunningApplicationInspector([])
        ).scan { _ in }
    }

    @Test("An empty plist is offered")
    func emptyIsOffered() async throws {
        try await withPreferences { home, prefs in
            try Data().write(to: prefs.appendingPathComponent("com.example.empty.plist"))
            let items = try await scan(home: home)
            #expect(items.map(\.displayName) == ["com.example.empty.plist"])
        }
    }

    @Test("A garbled plist is offered, a valid one is not")
    func garbledOnly() async throws {
        try await withPreferences { home, prefs in
            try Data("not a plist".utf8).write(to: prefs.appendingPathComponent("com.example.bad.plist"))
            try PropertyListSerialization.data(fromPropertyList: ["a": 1], format: .xml, options: 0)
                .write(to: prefs.appendingPathComponent("com.example.good.plist"))
            let items = try await scan(home: home)
            #expect(items.map(\.displayName) == ["com.example.bad.plist"])
        }
    }

    @Test("A file that cannot be read is not called broken")
    func unreadableIsNotBroken() async throws {
        try await withPreferences { home, prefs in
            let locked = prefs.appendingPathComponent("locked.plist")
            try Data("not a plist".utf8).write(to: locked)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
            let items = try await scan(home: home)
            #expect(items.isEmpty)
        }
    }

    @Test("Apple's own preferences are never offered, even when empty")
    func appleIsExcluded() async throws {
        try await withPreferences { home, prefs in
            try Data().write(to: prefs.appendingPathComponent("com.apple.something.plist"))
            #expect(try await scan(home: home).isEmpty)
        }
    }

    @Test("Nothing is preselected")
    func nothingPreselected() async throws {
        try await withPreferences { home, prefs in
            try Data().write(to: prefs.appendingPathComponent("com.example.empty.plist"))
            #expect(try await scan(home: home).defaultSelection().isEmpty)
        }
    }
}
