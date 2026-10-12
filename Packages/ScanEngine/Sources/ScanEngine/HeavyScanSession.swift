import Foundation
import Observation
import CoreKit

/// Runs one heavy scanner and exposes what the screen needs: live progress, a remaining-time
/// estimate, partial results, and a cancel that keeps what was found.
@Observable
@MainActor
public final class HeavyScanSession {
    public enum State: Sendable {
        case idle
        case running(ScanProgress, remaining: TimeInterval?)
        /// `wasCancelled` results are partial: whatever was found before the user stopped it.
        case finished(wasCancelled: Bool)
        case failed(ScanFailure)
    }

    /// A scan error reduced to something that is `Sendable` and comparable.
    public enum ScanFailure: Sendable, Equatable {
        case fullDiskAccessRequired
        case other(String)
    }

    public private(set) var state: State = .idle

    /// Everything found so far; grows during the scan and is final once it finishes.
    public private(set) var items: [ScanItem] = []

    private let scanner: any HeavyScanning
    private let clock: @Sendable () -> Date
    private var task: Task<Void, Never>?

    public init(scanner: any HeavyScanning, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.scanner = scanner
        self.clock = clock
    }

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    public func start() {
        guard !isRunning else { return }
        items = []
        state = .running(.starting, remaining: nil)

        let scanner = scanner
        let clock = clock
        task = Task { [weak self] in
            let board = SessionBoard(estimator: RemainingTimeEstimator(startedAt: clock()))
            do {
                let found = try await scanner.scan(
                    progress: { progress in
                        // At most 20 updates a second (CLAUDE.md §8).
                        guard let update = board.update(progress, now: clock()) else { return }
                        Task { @MainActor in
                            self?.state = .running(update.progress, remaining: update.remaining)
                        }
                    },
                    partial: { partial in
                        board.setPartial(partial)
                        Task { @MainActor in self?.items = partial }
                    }
                )
                await MainActor.run { [weak self] in
                    self?.items = found
                    self?.state = .finished(wasCancelled: false)
                }
            } catch is CancellationError {
                let kept = board.latestPartial()
                await MainActor.run { [weak self] in
                    self?.items = kept
                    self?.state = .finished(wasCancelled: true)
                }
            } catch ScanError.cancelled {
                let kept = board.latestPartial()
                await MainActor.run { [weak self] in
                    self?.items = kept
                    self?.state = .finished(wasCancelled: true)
                }
            } catch ScanError.fullDiskAccessRequired {
                await MainActor.run { [weak self] in self?.state = .failed(.fullDiskAccessRequired) }
            } catch {
                await MainActor.run { [weak self] in self?.state = .failed(.other("\(error)")) }
            }
        }
    }

    /// Stops the scan. What was found so far stays in `items`.
    public func cancel() {
        task?.cancel()
    }

    /// Waits for the current run to end. Mainly for tests.
    public func waitUntilFinished() async {
        await task?.value
    }
}

/// Shared between the scanner's threads and the main actor, so it sits behind a lock.
private final class SessionBoard: @unchecked Sendable {
    private let lock = NSLock()
    private var estimator: RemainingTimeEstimator
    private var partial: [ScanItem] = []
    private var lastPublish = Date.distantPast

    init(estimator: RemainingTimeEstimator) {
        self.estimator = estimator
    }

    func update(_ progress: ScanProgress, now: Date) -> (progress: ScanProgress, remaining: TimeInterval?)? {
        lock.lock()
        defer { lock.unlock() }
        let remaining = estimator.update(fraction: progress.fraction, now: now)
        guard now.timeIntervalSince(lastPublish) >= 0.05 else { return nil }
        lastPublish = now
        return (progress, remaining)
    }

    func setPartial(_ items: [ScanItem]) {
        lock.lock()
        partial = items
        lock.unlock()
    }

    func latestPartial() -> [ScanItem] {
        lock.lock()
        defer { lock.unlock() }
        return partial
    }
}
