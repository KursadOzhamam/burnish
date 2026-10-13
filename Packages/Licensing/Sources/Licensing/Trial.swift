import Foundation

/// The 14-day trial (CLAUDE.md §11.3): every Pro feature open, no card, and nothing taken hostage
/// when it ends.
public struct TrialRecord: Codable, Sendable, Equatable {
    public let startedAt: Date
    /// The latest time ever observed. Used so winding the clock back cannot extend the trial.
    public let lastSeen: Date

    public init(startedAt: Date, lastSeen: Date) {
        self.startedAt = startedAt
        self.lastSeen = lastSeen
    }
}

/// Where the trial record is kept. A protocol: the real store lives in the support folder (and the
/// Keychain, §11.3); tests use memory.
public protocol TrialStoring: Sendable {
    func load() -> TrialRecord?
    func save(_ record: TrialRecord)
}

public final class InMemoryTrialStore: TrialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var record: TrialRecord?

    public init(_ record: TrialRecord? = nil) { self.record = record }
    public func load() -> TrialRecord? { lock.withLock { record } }
    public func save(_ record: TrialRecord) { lock.withLock { self.record = record } }
}

/// A trial record in a JSON file. Easy to reset, and that is accepted (§11.3): an honest user is
/// not punished by aggressive measures against a dishonest one.
public final class FileTrialStore: TrialStoring, @unchecked Sendable {
    private let url: URL

    public init(url: URL) { self.url = url }

    public func load() -> TrialRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TrialRecord.self, from: data)
    }

    public func save(_ record: TrialRecord) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(record).write(to: url)
    }
}

public struct Trial: Sendable {
    public static let lengthInDays = 14

    private let store: any TrialStoring

    public init(store: any TrialStoring) { self.store = store }

    /// Whole days left at `now`, or nil when the trial is over. Starts the trial on first call.
    ///
    /// The clock is read as `max(now, lastSeen)`: winding it back never gives time back, and a
    /// clock set far ahead can only shorten the trial, which keeps honest users safe from a
    /// confused clock and costs a dishonest one nothing they did not already have.
    public func daysRemaining(now: Date) -> Int? {
        let record = store.load() ?? TrialRecord(startedAt: now, lastSeen: now)
        let effectiveNow = max(now, record.lastSeen)
        store.save(TrialRecord(startedAt: record.startedAt, lastSeen: effectiveNow))
        let elapsed = effectiveNow.timeIntervalSince(record.startedAt) / 86_400
        let left = Double(Self.lengthInDays) - elapsed
        return left > 0 ? Int(left.rounded(.up)) : nil
    }
}
