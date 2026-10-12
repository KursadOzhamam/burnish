import Foundation
import AppKit

/// Knows which applications are running, so their files can be left alone (CLAUDE.md §4.5).
public protocol RunningApplicationInspecting: Sendable {
    /// Bundle identifiers of everything currently running.
    func runningBundleIdentifiers() -> Set<String>
}

/// Live implementation backed by `NSWorkspace`.
public struct RunningApplicationInspector: RunningApplicationInspecting {
    public init() {}

    public func runningBundleIdentifiers() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}

/// Fixed set, for tests.
public struct StaticRunningApplicationInspector: RunningApplicationInspecting {
    private let identifiers: Set<String>

    public init(_ identifiers: Set<String> = []) {
        self.identifiers = identifiers
    }

    public func runningBundleIdentifiers() -> Set<String> { identifiers }
}

extension RunningApplicationInspecting {
    /// Finds the bundle identifier a path belongs to, if any.
    ///
    /// Recognises the container and support layouts where an app's files live under a folder
    /// named for its bundle id, e.g. `~/Library/Containers/com.apple.Safari/...`.
    func owningBundleIdentifier(of url: URL) -> String? {
        let running = runningBundleIdentifiers()
        guard !running.isEmpty else { return nil }
        // Reverse-DNS folder names are the reliable signal; matching on app name would catch
        // unrelated folders.
        return url.pathComponents.first { running.contains($0) }
    }
}
