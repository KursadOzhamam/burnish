import Testing
import Foundation
import CoreKit
import ScanEngine
import SafetyKit
import SafetyKitMac
@testable import Cleanup

/// Downloads is the user's own content: conservative, nothing preselected, folder never a target.
@Suite("Downloads", .serialized)
struct DownloadsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func withDownloads(_ body: (URL, URL) async throws -> Void) async throws {
        let home = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("BurnishDownloadsHome-\(UUID().uuidString)")
        let downloads = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer {
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: home)
        }
        try await body(home, downloads)
    }

    private func make(_ name: String, in folder: URL, daysOld: Double) throws {
        let url = folder.appendingPathComponent(name)
        try Data(repeating: 0x41, count: 4_096).write(to: url)
        let date = now.addingTimeInterval(-daysOld * 86_400)
        try FileManager.default.setAttributes(
            [.modificationDate: date], ofItemAtPath: url.path
        )
    }

    private func scan(home: URL) async throws -> [ScanItem] {
        try await CleanupScanner(
            rule: CleanupCatalogue.downloads,
            home: home,
            inspector: StaticRunningApplicationInspector([]),
            clock: { [now] in now }
        ).scan { _ in }
    }

    @Test("A finished installer is offered even when recent enough")
    func installerOffered() async throws {
        try await withDownloads { home, downloads in
            try make("App.dmg", in: downloads, daysOld: 3)
            let names = try await scan(home: home).map(\.displayName)
            #expect(names == ["App.dmg"])
        }
    }

    @Test("A file untouched for over 30 days is offered, a newer one is not")
    func ageThreshold() async throws {
        try await withDownloads { home, downloads in
            try make("old.pdf", in: downloads, daysOld: 45)
            try make("new.pdf", in: downloads, daysOld: 10)
            let names = try await scan(home: home).map(\.displayName)
            #expect(names == ["old.pdf"])
        }
    }

    @Test("A partial download is never offered, however old")
    func partialNeverOffered() async throws {
        try await withDownloads { home, downloads in
            try make("movie.mp4.crdownload", in: downloads, daysOld: 90)
            try make("thing.dmg.download", in: downloads, daysOld: 90)
            #expect(try await scan(home: home).isEmpty)
        }
    }

    @Test("Anything changed in the last day is never offered, even an installer")
    func veryRecentNeverOffered() async throws {
        try await withDownloads { home, downloads in
            try make("fresh.dmg", in: downloads, daysOld: 0.1)
            #expect(try await scan(home: home).isEmpty)
        }
    }

    @Test("Nothing is preselected")
    func nothingPreselected() async throws {
        try await withDownloads { home, downloads in
            try make("App.dmg", in: downloads, daysOld: 40)
            #expect(try await scan(home: home).defaultSelection().isEmpty)
        }
    }

    @Test("The Downloads folder itself is not removable; its contents are")
    func folderItselfProtected() async throws {
        try await withDownloads { home, downloads in
            let scanner = CleanupScanner(
                rule: CleanupCatalogue.downloads, home: home,
                inspector: StaticRunningApplicationInspector([])
            )
            let subject = PathGuard(allowedRoots: scanner.allowedRoots, allowedTargets: scanner.allowedTargets, home: home)
            #expect(!subject.isAllowed(downloads))
            #expect(subject.isAllowed(downloads.appendingPathComponent("App.dmg")))
        }
    }

    @Test("Downloads is never removed permanently")
    func neverPermanent() {
        #expect(!CleanupCatalogue.permanentScanners.contains(CleanupCatalogue.downloads.id))
    }
}
