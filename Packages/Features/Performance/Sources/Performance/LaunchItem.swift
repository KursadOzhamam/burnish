import Foundation

/// One launchd job that starts by itself: a login item, background agent or daemon
/// (CLAUDE.md §6.5). Read from the property list; nothing here changes anything.
public struct LaunchItem: Identifiable, Sendable, Hashable {
    public enum Scope: Sendable, Hashable {
        /// `~/Library/LaunchAgents`: the user's own.
        case userAgent
        /// `/Library/LaunchAgents`: installed for every user.
        case globalAgent
        /// `/Library/LaunchDaemons`: runs as root, before login.
        case daemon
    }

    public let label: String
    public let plistURL: URL
    public let scope: Scope
    /// The executable it starts, if the plist names one.
    public let program: String?
    public let runsAtLoad: Bool
    public let keepsAlive: Bool

    public var id: String { plistURL.path }

    /// The job starts a program that is no longer there.
    public var isProgramMissing: Bool {
        guard let program else { return false }
        return !FileManager.default.fileExists(atPath: program)
    }

    /// Apple's own jobs are never offered for change.
    public var isApple: Bool { label.hasPrefix("com.apple.") }

    /// Whether Burnish can switch this one off without administrator rights: a per-user job
    /// that is not Apple's. A daemon needs the helper (CLAUDE.md §7).
    public var canBeDisabledByUser: Bool { !isApple && scope != .daemon }

    public init(
        label: String, plistURL: URL, scope: Scope, program: String?, runsAtLoad: Bool, keepsAlive: Bool
    ) {
        self.label = label
        self.plistURL = plistURL
        self.scope = scope
        self.program = program
        self.runsAtLoad = runsAtLoad
        self.keepsAlive = keepsAlive
    }
}
