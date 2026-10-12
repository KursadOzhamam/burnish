import Foundation

/// Locations that are never touched, whatever a scanner proposes.
///
/// This is the list in CLAUDE.md §4.3, and it is the most consequential code in the project:
/// a mistake here loses somebody's data. Two properties matter.
///
/// 1. **Prefix matching, not equality.** Protecting `/System` protects everything beneath it.
/// 2. **No way to opt out.** There is no override flag and no "advanced" switch. A path that
///    matches is refused, full stop.
///
/// `SafetyKitMacTests` asserts every entry individually, so an accidental deletion from this
/// list fails the build rather than shipping.
public enum ProtectedPaths {
    /// Absolute roots that are protected along with their contents.
    public static let systemRoots: [String] = [
        "/System",
        "/bin",
        "/sbin",
        "/private/var/db",
        "/Library/Apple",
        "/Library/Developer/CommandLineTools",
        "/Library/Keychains",
        "/Library/Application Support/com.apple.TCC",
        "/private/var/folders"
    ]

    /// `/usr` is protected except for `/usr/local`, which is where Homebrew and friends live.
    public static let partiallyProtectedRoots: [(root: String, exception: String)] = [
        ("/usr", "/usr/local")
    ]

    /// Paths relative to the user's home directory, protected with their contents.
    ///
    /// These are the folders themselves — §4.3 protects `Documents` as a container. A scanner
    /// may still propose a specific file further inside only if its own allowlisted root lies
    /// there, which none of the cleanup scanners do.
    public static let homeRelative: [String] = [
        "Documents",
        "Desktop",
        "Pictures",
        "Movies",
        "Music",
        "Library/Keychains",
        "Library/Mobile Documents",     // iCloud Drive
        "Library/Mail",                  // mailbox data; only the attachment cache is cleanable
        ".ssh",
        ".gnupg"
    ]

    /// Bundle and package extensions that are never entered or removed wholesale.
    public static let protectedPackageExtensions: Set<String> = [
        "photoslibrary",
        "sparsebundle",
        "backupdb"
    ]

    /// Path components that mark a Time Machine backup or a volume index.
    public static let protectedComponents: Set<String> = [
        "Backups.backupdb",
        ".Spotlight-V100",
        ".fseventsd",
        ".DocumentRevisions-V100"
    ]

    /// Resolved absolute protected roots for the given home directory.
    public static func absoluteRoots(home: URL) -> [String] {
        systemRoots + homeRelative.map { home.appendingPathComponent($0).path }
    }
}
