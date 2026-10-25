import Foundation
import HelperProtocol

/// The maintenance jobs CLAUDE.md §6.5 lists. A closed set: each case maps to one fixed command,
/// so no caller can ask for anything else (§10.8). What each does is stated in plain words, and
/// none is sold as a speed-up: their measurable benefit is limited (§6.5, honesty note).
public enum MaintenanceTask: String, Sendable, CaseIterable, Identifiable {
    case flushDNS
    case rebuildLaunchServices
    case reindexSpotlight
    case verifyDisk
    case purgeMemory
    case runPeriodicScripts
    case resetQuickLook
    case resetFontCache

    public var id: String { rawValue }

    /// The helper command that carries this task out, if it needs administrator rights.
    public var helperCommand: HelperCommand? {
        switch self {
        case .rebuildLaunchServices, .resetQuickLook, .resetFontCache: nil
        case .flushDNS: .flushDNS
        case .reindexSpotlight: .reindexSpotlight
        case .verifyDisk: .verifyDisk
        case .purgeMemory: .purgeMemory
        case .runPeriodicScripts: .runPeriodicScripts
        }
    }

    /// Whether the command needs administrator rights, i.e. the privileged helper (CLAUDE.md §7).
    public var requiresHelper: Bool { helperCommand != nil }

    /// The fixed command: executable and arguments. Nothing is interpolated. The helper's
    /// commands are the helper's own table, so the two cannot drift apart.
    public var command: (executable: String, arguments: [String]) {
        if let helperCommand { return helperCommand.command }
        switch self {
        // Both reset only the current user's caches, which is why they need no helper.
        case .resetQuickLook:
            return ("/usr/bin/qlmanage", ["-r", "cache"])
        case .resetFontCache:
            return ("/usr/bin/atsutil", ["databases", "-removeUser"])
        default:
            return (
                "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                ["-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"]
            )
        }
    }
}
