import Foundation

/// A refusal from the safety layer.
///
/// These are policy decisions, not I/O errors: each one means the layer declined to act.
public enum SafetyError: Error, Sendable, Equatable {
    /// The path is on the protected list and is never touched (CLAUDE.md §4.3).
    case protectedPath(String)

    /// The path lies outside the scanner's declared root (§4.2).
    case outsideAllowlist(path: String, root: String)

    /// A symlink resolved to somewhere not allowed (§4.4).
    case symlinkEscape(from: String, to: String)

    /// The owning application is running (§4.5).
    case ownerRunning(bundleIdentifier: String?)

    /// Permanent deletion was requested without the extra confirmation (§4.1).
    case missingIrreversibleConfirmation
}
