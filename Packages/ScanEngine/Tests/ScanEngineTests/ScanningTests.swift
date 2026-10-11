import Testing
import Foundation
import CoreKit
@testable import ScanEngine

/// Minimal conformance used to check the protocol's defaults.
private struct StubScanner: Scanning {
    let id = ScannerID("stub")
    let title: LocalizedStringResource = "Stub"
    let items: [ScanItem]

    func scan(progress: @Sendable (ScanProgress) -> Void) async throws -> [ScanItem] {
        progress(ScanProgress(fraction: 0.5, currentPath: "/tmp", itemCount: items.count))
        return items
    }
}

@Suite("Scanning protocol")
struct ScannerTests {
    @Test("Defaults keep scanners out of the heavy path and off Full Disk Access")
    func protocolDefaults() {
        let scanner = StubScanner(items: [])
        #expect(scanner.weight == .light)
        #expect(scanner.requiresFullDiskAccess == false)
    }

    @Test("Scanning reports progress and returns items")
    func scanReportsProgress() async throws {
        let expected = ScanItem(
            scanner: ScannerID("stub"),
            url: URL(fileURLWithPath: "/tmp/x"),
            size: .megabytes(2)
        )
        let scanner = StubScanner(items: [expected])

        final class Box: @unchecked Sendable { var reports: [ScanProgress] = [] }
        let box = Box()

        let result = try await scanner.scan { box.reports.append($0) }

        #expect(result.count == 1)
        #expect(result[0].size == .megabytes(2))
        #expect(box.reports.count == 1)
        #expect(box.reports.first?.fraction == 0.5)
    }
}
