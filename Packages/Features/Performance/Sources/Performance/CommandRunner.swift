import Foundation

/// Runs a fixed tool with fixed arguments (CLAUDE.md §10.8).
///
/// The only way Burnish starts another program from the app side. It never builds a shell
/// string: an executable path and an argument array go to `Process` directly, and every caller
/// builds those from a closed set (an enum case plus a validated label), never from free text.
public protocol CommandRunning: Sendable {
    func run(_ executable: String, arguments: [String]) async throws -> CommandResult
}

public struct CommandResult: Sendable, Equatable {
    public let status: Int32
    public let output: String

    public init(status: Int32, output: String) {
        self.status = status
        self.output = output
    }

    public var succeeded: Bool { status == 0 }
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            // Fixed executable and argument array from a closed set; never a shell (decision 2026-10-13).
            // swiftlint:disable:next no_shell_in_helper
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { finished in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: CommandResult(
                    status: finished.terminationStatus, output: String(decoding: data, as: UTF8.self)
                ))
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}
