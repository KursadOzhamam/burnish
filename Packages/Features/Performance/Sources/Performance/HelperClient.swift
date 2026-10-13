import Foundation
import CoreKitMac
import ServiceManagement
import HelperProtocol

/// Where the privileged helper stands, in terms the user can act on (CLAUDE.md §7, risk R6).
public enum HelperStatus: Sendable, Equatable {
    case notRegistered
    /// Registered, but the user has not yet allowed it in System Settings > Login Items.
    case requiresApproval
    case enabled
    /// The launchd plist is missing from the app bundle: a broken install, not a user choice.
    case notFound
    /// An older helper is still running after the app was updated.
    case versionMismatch
    case failed(String)
}

/// What the Performance screens need from the helper. A protocol, so the screens and their
/// tests do not depend on a real root process.
public protocol HelperManaging: Sendable {
    func status() async -> HelperStatus
    /// Registers the helper. The user still has to approve it in System Settings.
    func install() async -> HelperStatus
    func openSettings()
    func run(_ command: HelperCommand) async throws -> CommandResult
    func removeSystemItems(_ paths: [String]) async throws -> [String]
}

/// The real helper client: `SMAppService` to install, XPC to talk.
public final class HelperClient: HelperManaging, @unchecked Sendable {
    public enum ClientError: Error, Sendable, Equatable {
        case notEnabled
        case connectionFailed(String)
        case unsigned
    }

    private let service = SMAppService.daemon(plistName: HelperIdentity.launchDaemonPlist)

    public init() {}

    public func status() async -> HelperStatus {
        switch service.status {
        case .notRegistered: return .notRegistered
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        case .enabled:
            // Running is not the same as current: ask it which protocol it speaks.
            if let version = try? await protocolVersion(), version != HelperIdentity.protocolVersion {
                return .versionMismatch
            }
            return .enabled
        @unknown default: return .failed("unknown status")
        }
    }

    public func install() async -> HelperStatus {
        do {
            try service.register()
        } catch {
            return .failed(error.localizedDescription)
        }
        return await status()
    }

    public func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: XPC

    private func connection() throws -> NSXPCConnection {
        // Pin the helper: our team, the helper's identifier. An ad-hoc build has no team, and
        // then no connection is made at all (fail closed).
        guard let team = CodeSigning.ownTeamID(), HelperRequirement.isValid(teamID: team) else { throw ClientError.unsigned }
        let connection = NSXPCConnection(machServiceName: HelperIdentity.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperXPC.self)
        connection.setCodeSigningRequirement(HelperRequirement.forHelper(teamID: team))
        connection.resume()
        return connection
    }

    private func protocolVersion() async throws -> Int {
        let connection = try connection()
        defer { connection.invalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: ClientError.connectionFailed(error.localizedDescription))
            } as? HelperXPC
            proxy?.protocolVersion { continuation.resume(returning: $0) }
        }
    }

    public func run(_ command: HelperCommand) async throws -> CommandResult {
        guard service.status == .enabled else { throw ClientError.notEnabled }
        let connection = try connection()
        defer { connection.invalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: ClientError.connectionFailed(error.localizedDescription))
            } as? HelperXPC
            proxy?.runCommand(command.rawValue) { status, output in
                continuation.resume(returning: CommandResult(status: status, output: output))
            }
        }
    }

    public func removeSystemItems(_ paths: [String]) async throws -> [String] {
        guard service.status == .enabled else { throw ClientError.notEnabled }
        let connection = try connection()
        defer { connection.invalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: ClientError.connectionFailed(error.localizedDescription))
            } as? HelperXPC
            proxy?.removeSystemItems(paths) { continuation.resume(returning: $0) }
        }
    }
}
