import Foundation

/// How an item is removed.
///
/// CLAUDE.md §4.1: moving to the Trash is the default, and permanent deletion happens only where
/// the user explicitly chose it (Shredder, emptying the Trash) and confirmed again. The enum has
/// no default value on purpose — every call site must state which it means.
public enum DeletionMode: String, Sendable, Codable, CaseIterable {
    /// `FileManager.trashItem`. Recoverable from the Trash and from the app's own history (§4.7).
    case trash

    /// Unrecoverable. Requires the extra confirmation described in §4.1.
    case permanent

    /// True when this mode destroys data irreversibly.
    public var isIrreversible: Bool { self == .permanent }

    /// The safe default used wherever the user has not chosen otherwise.
    public static let `default` = DeletionMode.trash
}
