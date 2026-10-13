import Foundation

/// Looks at what starts by itself and flags the odd ones (CLAUDE.md §6.4, persistence points).
///
/// Persistence is how most unwanted software survives a restart, so the launch folders are worth
/// reading. The checks are narrow on purpose: a job whose program is gone (information), and a
/// job that runs something from a place real software does not install to (suspicious). A job
/// being unfamiliar is not a finding.
public struct PersistenceAnalyzer: Sendable {
    public let home: URL
    public let folders: [URL]

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        extraFolders: [URL] = [URL(fileURLWithPath: "/Library/LaunchAgents"), URL(fileURLWithPath: "/Library/LaunchDaemons")]
    ) {
        self.home = home
        self.folders = [home.appendingPathComponent("Library/LaunchAgents")] + extraFolders
    }

    /// Places software does not normally install a launch job's program into.
    func isOddLocation(_ path: String) -> Bool {
        let hiddenComponent = path.split(separator: "/").contains { $0.hasPrefix(".") && $0 != ".." && $0 != "." }
        return path.hasPrefix("/tmp/") || path.hasPrefix("/private/tmp/") || path.hasPrefix("/var/tmp/")
            || path.hasPrefix("/Users/Shared/") || path.hasPrefix("/private/var/tmp/") || hiddenComponent
    }

    public func findings() -> [Finding] {
        var result: [Finding] = []
        for folder in folders {
            guard let entries = try? FileManager().contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for entry in entries where entry.pathExtension == "plist" {
                guard let data = try? Data(contentsOf: entry),
                      let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
                else { continue }
                let label = (plist["Label"] as? String) ?? entry.deletingPathExtension().lastPathComponent
                if label.hasPrefix("com.apple.") { continue }
                let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
                guard let program, program.hasPrefix("/") else { continue }
                if isOddLocation(program) {
                    result.append(Finding(url: entry, severity: .suspicious, reason: .hiddenLaunchItem(label: label)))
                } else if !FileManager.default.fileExists(atPath: program) {
                    result.append(Finding(url: entry, severity: .info, reason: .danglingLaunchItem(label: label)))
                }
            }
        }
        return result.sorted { $0.severity > $1.severity }
    }
}
