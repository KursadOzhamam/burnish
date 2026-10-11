import Testing
import Foundation
import CoreKit
@testable import ScanEngine

@Suite("ScanItem")
struct ScanItemTests {
    private let scanner = ScannerID("test.scanner")

    private func item(
        name: String = "cache",
        size: Int64 = 100,
        confidence: ScanItem.Confidence = .high,
        children: [ScanItem] = [],
        blocked: ScanItem.BlockedReason? = nil
    ) -> ScanItem {
        ScanItem(
            scanner: scanner,
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            size: ByteCount(size),
            confidence: confidence,
            children: children,
            blockedReason: blocked
        )
    }

    @Test("Display name falls back to the last path component")
    func displayNameFallback() {
        #expect(item(name: "Caches").displayName == "Caches")
    }

    @Test("Total size includes nested children recursively")
    func totalSizeIsRecursive() {
        let leaf = item(size: 5)
        let middle = item(size: 10, children: [leaf, leaf])
        let root = item(size: 100, children: [middle])
        // 100 + (10 + 5 + 5)
        #expect(root.totalSize.bytes == 120)
    }

    @Test("Low confidence items are not preselected", arguments: ScanItem.Confidence.allCases)
    func preselectionRespectsConfidence(confidence: ScanItem.Confidence) {
        let subject = item(confidence: confidence)
        #expect(subject.isSelectedByDefault == (confidence != .low))
    }

    @Test("Blocked items are never actionable or preselected",
          arguments: ScanItem.BlockedReason.allCases)
    func blockedItemsAreInert(reason: ScanItem.BlockedReason) {
        let subject = item(confidence: .high, blocked: reason)
        #expect(!subject.isActionable)
        #expect(!subject.isSelectedByDefault)
    }

    @Test("Default selection filters out low confidence and blocked items")
    func defaultSelectionFilters() {
        let items = [
            item(name: "a", confidence: .high),
            item(name: "b", confidence: .medium),
            item(name: "c", confidence: .low),
            item(name: "d", confidence: .high, blocked: .ownerRunning)
        ]
        #expect(items.defaultSelection().count == 2)
    }

    @Test("Sequence total size sums children too")
    func sequenceTotal() {
        let items = [item(size: 10, children: [item(size: 1)]), item(size: 20)]
        #expect(items.totalSize().bytes == 31)
    }

    @Test("Confidence is ordered low < medium < high")
    func confidenceOrdering() {
        #expect(ScanItem.Confidence.low < .medium)
        #expect(ScanItem.Confidence.medium < .high)
    }
}

@Suite("ScanProgress")
struct ScanProgressTests {
    @Test("Fraction is clamped to 0...1")
    func fractionClamped() {
        #expect(ScanProgress(fraction: 1.5).fraction == 1)
        #expect(ScanProgress(fraction: -0.5).fraction == 0)
    }

    @Test("Absent fraction means indeterminate")
    func indeterminate() {
        #expect(ScanProgress.starting.isIndeterminate)
        #expect(!ScanProgress(fraction: 0).isIndeterminate)
    }

    @Test("Negative item count clamps to zero")
    func itemCountClamped() {
        #expect(ScanProgress(itemCount: -3).itemCount == 0)
    }
}
