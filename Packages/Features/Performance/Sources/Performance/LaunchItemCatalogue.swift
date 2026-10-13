import Foundation

/// Lists launchd jobs from the three standard folders. Reads only.
public struct LaunchItemCatalogue: Sendable {
    public let home: URL
    public let globalAgents: URL
    public let daemons: URL

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        globalAgents: URL = URL(fileURLWithPath: "/Library/LaunchAgents"),
        daemons: URL = URL(fileURLWithPath: "/Library/LaunchDaemons")
    ) {
        self.home = home
        self.globalAgents = globalAgents
        self.daemons = daemons
    }

    public func items() -> [LaunchItem] {
        let sources: [(URL, LaunchItem.Scope)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), .userAgent),
            (globalAgents, .globalAgent),
            (daemons, .daemon)
        ]
        var result: [LaunchItem] = []
        for (folder, scope) in sources {
            guard let entries = try? FileManager().contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for entry in entries where entry.pathExtension == "plist" {
                if let item = Self.parse(entry, scope: scope) { result.append(item) }
            }
        }
        return result.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    /// Reads one property list. Nil when it cannot be read or has no label.
    static func parse(_ url: URL, scope: LaunchItem.Scope) -> LaunchItem? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        let label = (plist["Label"] as? String) ?? url.deletingPathExtension().lastPathComponent
        let arguments = plist["ProgramArguments"] as? [String]
        let program = (plist["Program"] as? String) ?? arguments?.first
        let keepAlive: Bool
        switch plist["KeepAlive"] {
        case let flag as Bool: keepAlive = flag
        case is [String: Any]: keepAlive = true
        default: keepAlive = false
        }
        return LaunchItem(
            label: label, plistURL: url, scope: scope, program: program,
            runsAtLoad: plist["RunAtLoad"] as? Bool ?? false, keepsAlive: keepAlive
        )
    }
}
