import Testing
import Foundation
import CoreKit
@testable import ScanEngine

@Suite("Remaining time estimate")
struct RemainingTimeEstimatorTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test("Says nothing until there is enough evidence")
    func tooEarly() {
        var estimator = RemainingTimeEstimator(startedAt: start)
        #expect(estimator.update(fraction: 0.01, now: start.addingTimeInterval(10)) == nil)
        #expect(estimator.update(fraction: 0.5, now: start.addingTimeInterval(1)) == nil)
        #expect(estimator.update(fraction: nil, now: start.addingTimeInterval(10)) == nil)
    }

    @Test("Extrapolates linearly: half done after 10 s leaves about 10 s")
    func linear() {
        var estimator = RemainingTimeEstimator(startedAt: start)
        let remaining = estimator.update(fraction: 0.5, now: start.addingTimeInterval(10))
        #expect(remaining == 10)
    }

    @Test("Finished work has nothing left")
    func finished() {
        var estimator = RemainingTimeEstimator(startedAt: start)
        #expect(estimator.update(fraction: 1, now: start.addingTimeInterval(5)) == 0)
    }

    @Test("A single slow sample does not double the estimate")
    func smoothing() {
        var estimator = RemainingTimeEstimator(startedAt: start)
        _ = estimator.update(fraction: 0.5, now: start.addingTimeInterval(10))
        let next = estimator.update(fraction: 0.5, now: start.addingTimeInterval(20))
        #expect(next != nil && next! < 20, "raw would be 20, smoothing keeps it below")
    }
}

private struct SlowScanner: HeavyScanning {
    let id = ScannerID("heavy.stub")
    let title: LocalizedStringResource = "Stub"
    let batches: Int

    func scan(
        progress: @Sendable (ScanProgress) -> Void,
        partial: @Sendable ([ScanItem]) -> Void
    ) async throws -> [ScanItem] {
        var found: [ScanItem] = []
        for index in 0..<batches {
            try Task.checkCancellation()
            found.append(ScanItem(scanner: id, url: URL(fileURLWithPath: "/tmp/\(index)"), size: ByteCount(10)))
            partial(found)
            progress(ScanProgress(fraction: Double(index + 1) / Double(batches), itemCount: found.count))
            try await Task.sleep(for: .milliseconds(20))
        }
        return found
    }
}

@Suite("Heavy scan session")
@MainActor
struct HeavyScanSessionTests {
    @Test("A heavy scanner defaults to the heavy weight")
    func weight() {
        #expect(SlowScanner(batches: 1).weight == .heavy)
    }

    @Test("A finished scan keeps all its items")
    func completes() async {
        let session = HeavyScanSession(scanner: SlowScanner(batches: 3))
        session.start()
        await session.waitUntilFinished()
        #expect(session.items.count == 3)
        if case .finished(let cancelled) = session.state { #expect(!cancelled) } else { Issue.record("not finished") }
    }

    @Test("Cancelling keeps what was found so far and marks the result partial")
    func cancelKeepsPartial() async throws {
        let session = HeavyScanSession(scanner: SlowScanner(batches: 500))
        session.start()
        try await Task.sleep(for: .milliseconds(150))
        session.cancel()
        await session.waitUntilFinished()

        #expect(!session.items.isEmpty, "partial results survive a cancel")
        #expect(session.items.count < 500)
        if case .finished(let cancelled) = session.state { #expect(cancelled) } else { Issue.record("not finished") }
    }

    @Test("A scan that needs Full Disk Access fails with that reason, not a generic one")
    func permissionFailure() async {
        struct Needy: HeavyScanning {
            let id = ScannerID("heavy.needy")
            let title: LocalizedStringResource = "Needy"
            func scan(progress: @Sendable (ScanProgress) -> Void,
                      partial: @Sendable ([ScanItem]) -> Void) async throws -> [ScanItem] {
                throw ScanError.fullDiskAccessRequired
            }
        }
        let session = HeavyScanSession(scanner: Needy())
        session.start()
        await session.waitUntilFinished()
        if case .failed(let reason) = session.state { #expect(reason == .fullDiskAccessRequired) } else { Issue.record("not failed") }
    }

    @Test("Starting twice while running does not restart")
    func noDoubleStart() async {
        let session = HeavyScanSession(scanner: SlowScanner(batches: 5))
        session.start()
        session.start()
        await session.waitUntilFinished()
        #expect(session.items.count == 5)
    }
}
