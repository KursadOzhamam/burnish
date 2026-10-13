import Foundation

/// The user's "this is safe, do not ask again" decisions (CLAUDE.md §6.4, false-positive policy).
///
/// Keyed by path *and* kind of reason, so allowing a file for one reason does not silence a
/// different, newer finding about the same file.
public struct AllowList: Codable, Sendable, Equatable {
    public private(set) var keys: Set<String> = []

    public init(keys: Set<String> = []) {
        self.keys = keys
    }

    static func key(for finding: Finding) -> String {
        "\(finding.url.path)|\(String(describing: finding.reason).prefix { $0 != "(" })"
    }

    public func allows(_ finding: Finding) -> Bool { keys.contains(Self.key(for: finding)) }

    public mutating func allow(_ finding: Finding) { keys.insert(Self.key(for: finding)) }

    public mutating func revoke(_ finding: Finding) { keys.remove(Self.key(for: finding)) }

    public func filtering(_ findings: [Finding]) -> [Finding] { findings.filter { !allows($0) } }

    // MARK: Persistence

    public static func load(from url: URL) -> AllowList {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(AllowList.self, from: $0) } ?? AllowList()
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url)
    }
}
