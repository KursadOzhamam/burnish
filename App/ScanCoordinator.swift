import Foundation
import Observation
import CoreKit
import ScanEngine
import SmartScan

/// Drives a simulated scan so the signature animation can be judged in Phase 1.
///
/// Phase 4 replaces `run()` with a real `TaskGroup` over the `.light` scanners (CLAUDE.md §6.2);
/// the published `ScanPhase` contract stays the same, so `SmartScanView` will not change.
@Observable
@MainActor
final class ScanCoordinator {
    var phase: ScanPhase = .idle

    private var task: Task<Void, Never>?

    /// Folders named during the simulated run. Real paths, so the animation is paced by strings
    /// of realistic length rather than placeholders.
    private static let samplePaths = [
        "~/Library/Caches/com.apple.Safari/WebKitCache",
        "~/Library/Developer/Xcode/DerivedData",
        "~/Library/Developer/Xcode/iOS DeviceSupport",
        "~/Library/Caches/Homebrew/downloads",
        "~/Library/Logs/DiagnosticReports",
        "~/Library/Containers/com.apple.mail/Data/Library/Caches",
        "/Library/Caches/com.apple.iconservices.store",
        "~/Library/Application Support/Code/CachedExtensions",
        "~/Library/Caches/Google/Chrome/Default/Cache",
        "~/.npm/_cacache",
        "~/Library/Caches/pip/wheels",
        "~/Library/Saved Application State"
    ]

    func start() {
        cancel()
        phase = .scanning(.starting)

        task = Task { [weak self] in
            var discovered = ByteCount.zero
            var itemCount = 0
            let steps = Self.samplePaths.count

            for (index, path) in Self.samplePaths.enumerated() {
                // Cancellation must be honoured promptly (§8).
                if Task.isCancelled { return }

                discovered += .megabytes(Int64.random(in: 180...2_400))
                itemCount += Int.random(in: 40...600)

                self?.phase = .scanning(
                    ScanProgress(
                        fraction: Double(index + 1) / Double(steps),
                        currentPath: path,
                        discovered: discovered,
                        itemCount: itemCount
                    )
                )

                try? await Task.sleep(for: .milliseconds(420))
            }

            if Task.isCancelled { return }
            self?.phase = .finished(found: discovered, itemCount: itemCount)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase.isScanning {
            phase = .cancelled
        }
    }
}
