import Foundation

/// Everything the helper can be asked to do. A closed enum: the helper has no way to run
/// anything that is not a case here (CLAUDE.md §7, §10.8).
public enum HelperCommand: String, Sendable, CaseIterable, Codable {
    case flushDNS
    case reindexSpotlight
    case verifyDisk
    case purgeMemory
    case runPeriodicScripts
    case thinLocalSnapshots

    /// The fixed command: an absolute executable and its arguments. Nothing is interpolated.
    /// For a task of several steps, this is the first one.
    public var command: (executable: String, arguments: [String]) {
        steps[0]
    }

    /// Every fixed command the task runs, in order. Most tasks are one step.
    public var steps: [(executable: String, arguments: [String])] {
        switch self {
        case .flushDNS:
            // Clearing the directory-service cache alone leaves mDNSResponder answering from
            // its own cache, which is where most stale lookups live; the hang-up makes it drop it.
            [("/usr/bin/dscacheutil", ["-flushcache"]), ("/usr/bin/killall", ["-HUP", "mDNSResponder"])]
        case .reindexSpotlight: [("/usr/bin/mdutil", ["-E", "/"])]
        case .verifyDisk: [("/usr/sbin/diskutil", ["verifyVolume", "/"])]
        case .purgeMemory: [("/usr/sbin/purge", [])]
        case .runPeriodicScripts: [("/usr/sbin/periodic", ["daily", "weekly", "monthly"])]
        // Asks macOS to reclaim as much space from local snapshots as it can, at the highest
        // urgency. macOS still decides which snapshots go; nothing is named by us.
        case .thinLocalSnapshots: [("/usr/bin/tmutil", ["thinlocalsnapshots", "/", "999999999999", "4"])]
        }
    }
}
