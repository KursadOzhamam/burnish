import Foundation
import ScanEngine

/// What a protection scan reports about one item (CLAUDE.md §6.4).
///
/// Every finding carries a reason in plain words, because a bare "flagged" is not acceptable:
/// the user must be able to see *why*, and to say "this is safe, do not ask again" (§6.4,
/// false-positive policy). Nothing is deleted on the strength of a finding; the only action
/// offered is moving the item to quarantine, which can be undone.
public struct Finding: Identifiable, Sendable, Hashable {
    public enum Severity: Int, Sendable, Comparable {
        /// Worth knowing, not a problem on its own (an unsigned app that came from the internet).
        case info = 0
        /// Matches a pattern that is often malicious but is not proof.
        case suspicious = 1
        /// Matches a known-bad file exactly (hash blocklist).
        case threat = 2

        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public enum Reason: Sendable, Hashable {
        case knownBadHash(name: String)
        case ruleMatch(rule: String, description: String)
        case unsignedFromInternet
        case invalidSignature
        case danglingLaunchItem(label: String)
        case hiddenLaunchItem(label: String)
    }

    public let url: URL
    public let severity: Severity
    public let reason: Reason

    public var id: String { "\(url.path)#\(reason)" }

    public init(url: URL, severity: Severity, reason: Reason) {
        self.url = url
        self.severity = severity
        self.reason = reason
    }
}
