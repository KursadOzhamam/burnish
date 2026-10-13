import Foundation
import SafetyKit
import SafetyKitMac

/// The rules the helper applies on its own side, whatever the app sends (CLAUDE.md §4.10).
///
/// The helper runs as root, so it trusts nothing it is handed: not the path, not the claim that
/// the app already checked it. Removal is limited to the contents of a short list of system
/// folders, passes through the same `PathGuard` the app uses, and refuses anything that resolves
/// elsewhere.
public struct HelperPolicy: Sendable {
    /// System folders whose *contents* may be removed. The folders themselves never are.
    public static let removableRoots: [String] = ["/Library/Caches", "/Library/Logs"]

    public enum Refusal: Error, Sendable, Equatable {
        case notAbsolute
        case outsideAllowedRoots
        case protectedPath
        case isRoot
    }

    private let guardrail: PathGuard

    public init(home: URL = URL(fileURLWithPath: "/var/root")) {
        guardrail = PathGuard(allowedRoots: Self.removableRoots.map { URL(fileURLWithPath: $0) }, home: home)
    }

    /// Decides whether `path` may be removed. Symlinks are resolved first and the *result* is
    /// checked, so a link inside an allowed folder cannot point the removal elsewhere (§4.4).
    public func validate(_ path: String) throws -> URL {
        guard path.hasPrefix("/") else { throw Refusal.notAbsolute }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        if Self.removableRoots.contains(url.path) { throw Refusal.isRoot }
        let resolved = url.resolvingSymlinksInPath()
        guard Self.removableRoots.contains(where: { resolved.path.hasPrefix($0 + "/") }) else {
            throw Refusal.outsideAllowedRoots
        }
        guard guardrail.isAllowed(resolved) else { throw Refusal.protectedPath }
        return resolved
    }

    /// Whether a raw command name is one the helper knows.
    public static func command(named rawValue: String) -> HelperCommand? {
        HelperCommand(rawValue: rawValue)
    }
}

/// The code-signing requirement a connecting client must satisfy: our app, signed by our team.
public enum HelperRequirement {
    /// - Parameter teamID: the Apple team identifier of the signer.
    public static func forMainApp(teamID: String) -> String {
        "anchor apple generic and identifier \"\(HelperIdentity.appIdentifier)\" and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    /// A team identifier is ten letters and digits. Anything else is refused before it reaches
    /// a requirement string.
    public static func isValid(teamID: String) -> Bool {
        teamID.count == 10 && teamID.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
    }
}
