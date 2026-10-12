import Foundation

/// Decides which top-level entries of the Downloads folder are worth offering.
///
/// Downloads is the user's own content, so the rule is conservative: an entry is offered only
/// when it is a finished installer or has gone untouched for a long time, and an entry that
/// might still be arriving is never offered.
enum DownloadsFilter {
    static let installerExtensions: Set<String> = ["dmg", "pkg", "iso", "xip"]

    /// Extensions browsers use for a file that is still being written.
    static let partialExtensions: Set<String> = ["crdownload", "download", "part", "opdownload", "partial"]

    enum Reason: Equatable {
        case installer
        case untouched
    }

    /// Returns why the entry should be offered, or nil when it should not.
    static func reason(for url: URL, days: Int, now: Date) -> Reason? {
        let ext = url.pathExtension.lowercased()
        if partialExtensions.contains(ext) { return nil }

        let keys: Set<URLResourceKey> = [.contentAccessDateKey, .contentModificationDateKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        let lastTouched = [values.contentAccessDate, values.contentModificationDate]
            .compactMap { $0 }
            .max()
        guard let lastTouched else { return nil }

        // Something changed in the last day may still be downloading, or is simply new.
        if now.timeIntervalSince(lastTouched) < 24 * 3_600 { return nil }

        if installerExtensions.contains(ext) { return .installer }
        let cutoff = now.addingTimeInterval(-Double(days) * 24 * 3_600)
        return lastTouched < cutoff ? .untouched : nil
    }
}
