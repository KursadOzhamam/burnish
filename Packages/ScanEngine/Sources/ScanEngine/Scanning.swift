import Foundation

/// A unit of discovery.
///
/// A scanner only ever *reports*; it never deletes. Deletion goes through `SafetyKit`'s single
/// `DeletionService` (CLAUDE.md §4).
///
/// Named `Scanning` rather than `Scanner` because `Foundation.Scanner` is a concrete class: a
/// protocol called `Scanner` makes every `extension Scanner` in a file that imports Foundation
/// silently extend Foundation's class instead. Conforming types keep the `*Scanner` suffix
/// (`UserCacheScanner`, `DuplicateScanner`). See CLAUDE.md §17.
public protocol Scanning: Sendable {
    var id: ScannerID { get }
    var title: LocalizedStringResource { get }
    var requiresFullDiskAccess: Bool { get }
    var weight: ScannerWeight { get }
    func scan(progress: @Sendable (ScanProgress) -> Void) async throws -> [ScanItem]
}

extension Scanning {
    /// Most scanners read only their own allowlisted folders and need no special access.
    public var requiresFullDiskAccess: Bool { false }

    /// Scanners opt into `.heavy` deliberately; defaulting to `.light` would quietly break
    /// the Smart Scan budget in §8.
    public var weight: ScannerWeight { .light }
}

/// Why a scan ended without results.
public enum ScanError: Error, Sendable, Equatable {
    /// The user cancelled. Every scan must be cancellable (§8).
    case cancelled
    /// Full Disk Access is missing; the scanner is marked "permission required" rather than failed (§7).
    case fullDiskAccessRequired
    /// The privileged helper is not installed or not reachable (§7).
    case helperUnavailable
    /// The scanner's root folder does not exist on this machine.
    case rootUnavailable(String)
}
