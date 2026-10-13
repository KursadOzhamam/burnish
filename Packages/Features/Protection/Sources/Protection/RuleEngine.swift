import Foundation

/// Burnish's own pattern rules (CLAUDE.md §6.4).
///
/// A small, readable subset of what YARA does: a rule names byte or text patterns and says how
/// many must be present. It exists so the scan has a working signature engine without a native
/// dependency; binding the real YARA library behind the same `RuleMatching` interface is a later
/// step (decision log). Rules are data, so each one can be reviewed, and each carries a
/// description that is shown to the user when it fires.
public struct Rule: Codable, Sendable, Equatable {
    public enum Condition: String, Codable, Sendable { case any, all }

    public let id: String
    public let description: String
    /// ASCII text to look for.
    public let strings: [String]
    /// Raw byte sequences to look for, as hex (`"4d5a90"`).
    public let hex: [String]
    public let condition: Condition
    /// Smaller files only: a rule is not run on something too large to be a script or dropper.
    public let maxFileSize: Int

    public init(id: String, description: String, strings: [String] = [], hex: [String] = [], condition: Condition = .all, maxFileSize: Int = 5_000_000) {
        self.id = id
        self.description = description
        self.strings = strings
        self.hex = hex
        self.condition = condition
        self.maxFileSize = maxFileSize
    }

    var patterns: [Data] {
        strings.map { Data($0.utf8) } + hex.compactMap(Self.bytes(fromHex:))
    }

    static func bytes(fromHex text: String) -> Data? {
        let clean = text.filter { !$0.isWhitespace }
        guard clean.count.isMultiple(of: 2), !clean.isEmpty else { return nil }
        var data = Data()
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}

public protocol RuleMatching: Sendable {
    /// The rules that match the file at `url`.
    func matches(for url: URL, size: Int) -> [Rule]
}

public struct RuleEngine: RuleMatching {
    public let rules: [Rule]

    public init(rules: [Rule]) {
        self.rules = rules
    }

    public func matches(for url: URL, size: Int) -> [Rule] {
        let candidates = rules.filter { size <= $0.maxFileSize }
        guard !candidates.isEmpty, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
        return candidates.filter { rule in
            let patterns = rule.patterns
            guard !patterns.isEmpty else { return false }
            let found = patterns.map { data.range(of: $0) != nil }
            return rule.condition == .all ? found.allSatisfy { $0 } : found.contains(true)
        }
    }

    /// The rules shipped with the app. Deliberately conservative: patterns that describe a
    /// behaviour no honest script has a reason to contain, not words that merely sound bad.
    public static let builtIn: [Rule] = [
        Rule(
            id: "burnish.eicar",
            description: "The EICAR antivirus test file. Harmless; it exists to check that scanners work.",
            strings: ["X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*"],
            condition: .all,
            maxFileSize: 1_000
        ),
        Rule(
            id: "burnish.script.curl-pipe-shell-hidden",
            description: "A script that downloads code and pipes it straight into a shell from a hidden location.",
            strings: ["curl ", "| sh", "/.hidden"],
            condition: .all,
            maxFileSize: 200_000
        )
    ]
}
