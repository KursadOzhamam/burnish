import Foundation

/// Detects whether the app can read TCC-protected folders — CLAUDE.md §7.
///
/// There is no API that says "Full Disk Access granted". The reliable test is to try listing a
/// protected folder that exists on every account and see whether the system lets us.
public enum FullDiskAccess {

    /// Deep link to the Full Disk Access pane of System Settings.
    public static let settingsURLString =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    /// Protected folders present on essentially every Mac, in the order they are tried.
    public static func defaultProbes(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        [
            "Library/Safari",
            "Library/Application Support/com.apple.TCC",
            "Library/Mail"
        ].map { home.appendingPathComponent($0) }
    }

    /// - Returns: `true` if a protected folder could be listed, `false` if one exists and could
    ///   not, `nil` when none of the probes exist so nothing can be concluded. The first probe
    ///   that exists decides, because probes are interchangeable.
    public static func isGranted(probes: [URL] = defaultProbes()) -> Bool? {
        let fileManager = FileManager()
        for probe in probes where fileManager.fileExists(atPath: probe.path) {
            return (try? fileManager.contentsOfDirectory(atPath: probe.path)) != nil
        }
        return nil
    }
}
