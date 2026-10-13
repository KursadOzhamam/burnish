import Foundation

/// Everything the helper can be asked to do. A closed enum: the helper has no way to run
/// anything that is not a case here (CLAUDE.md §7, §10.8).
public enum HelperCommand: String, Sendable, CaseIterable, Codable {
    case flushDNS
    case reindexSpotlight
    case verifyDisk
    case purgeMemory
    case runPeriodicScripts

    /// The fixed command: an absolute executable and its arguments. Nothing is interpolated.
    public var command: (executable: String, arguments: [String]) {
        switch self {
        case .flushDNS: ("/usr/bin/dscacheutil", ["-flushcache"])
        case .reindexSpotlight: ("/usr/bin/mdutil", ["-E", "/"])
        case .verifyDisk: ("/usr/sbin/diskutil", ["verifyVolume", "/"])
        case .purgeMemory: ("/usr/sbin/purge", [])
        case .runPeriodicScripts: ("/usr/sbin/periodic", ["daily", "weekly", "monthly"])
        }
    }
}
