import Foundation

/// Switches a per-user launchd job on or off, reversibly (CLAUDE.md §6.5).
///
/// Uses `launchctl disable` / `enable`, which record the choice in launchd's own database. The
/// property list is never renamed or deleted, so switching back on restores exactly what was
/// there. Labels are validated before they reach a command line.
public struct LaunchControl: Sendable {
    public enum ControlError: Error, Sendable, Equatable {
        case invalidLabel
        case notAllowed
        case failed(String)
    }

    private let runner: any CommandRunning
    private let userID: UInt32

    public init(runner: any CommandRunning = ProcessCommandRunner(), userID: UInt32 = getuid()) {
        self.runner = runner
        self.userID = userID
    }

    /// A launchd label is reverse-DNS-like: letters, digits, dot, dash, underscore. Anything else
    /// (a slash, a space, a quote) is refused before any command is built.
    static func isValid(label: String) -> Bool {
        guard !label.isEmpty, label.count <= 200, !label.hasPrefix("-") else { return false }
        return label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") }
    }

    private var domain: String { "gui/\(userID)" }

    /// Labels currently switched off in the user's domain.
    public func disabledLabels() async throws -> Set<String> {
        let result = try await runner.run("/bin/launchctl", arguments: ["print-disabled", domain])
        guard result.succeeded else { throw ControlError.failed(result.output) }
        var labels = Set<String>()
        for line in result.output.split(separator: "\n") where line.contains("=>") {
            // Lines look like:   "com.example.agent" => disabled
            let parts = line.split(separator: "=>", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[1] == "disabled" || parts[1] == "true" else { continue }
            labels.insert(parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
        }
        return labels
    }

    /// Switches `item` off: disables it for next login and stops it now.
    public func disable(_ item: LaunchItem) async throws {
        try check(item)
        let target = "\(domain)/\(item.label)"
        let result = try await runner.run("/bin/launchctl", arguments: ["disable", target])
        guard result.succeeded else { throw ControlError.failed(result.output) }
        // Stopping it now is best effort: it may not be running.
        _ = try? await runner.run("/bin/launchctl", arguments: ["bootout", target])
    }

    /// Switches `item` back on.
    public func enable(_ item: LaunchItem) async throws {
        try check(item)
        let result = try await runner.run("/bin/launchctl", arguments: ["enable", "\(domain)/\(item.label)"])
        guard result.succeeded else { throw ControlError.failed(result.output) }
    }

    private func check(_ item: LaunchItem) throws {
        guard Self.isValid(label: item.label) else { throw ControlError.invalidLabel }
        guard item.canBeDisabledByUser else { throw ControlError.notAllowed }
    }
}
