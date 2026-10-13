import Foundation
import CoreKit
import CoreKitMac
import ScanEngine
import ServiceManagement
import HelperProtocol

/// Everything Burnish itself leaves on a Mac, and the means to take it away (CLAUDE.md §6.9):
/// "a cleaning app that leaves its own leftovers behind" is exactly what this exists to prevent.
public struct BurnishFootprint: Sendable {
    public static let scannerID = ScannerID("burnish.footprint")

    public let home: URL
    public let bundleIdentifier: String
    public let supportFolderName: String

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundleIdentifier: String = AppIdentity.current.bundleIdentifier,
        supportFolderName: String = AppIdentity.current.displayName
    ) {
        self.home = home
        self.bundleIdentifier = bundleIdentifier
        self.supportFolderName = supportFolderName
    }

    /// The data folders and files that exist now.
    public func items() -> [ScanItem] {
        let library = home.appendingPathComponent("Library")
        let candidates = [
            library.appendingPathComponent("Application Support/\(supportFolderName)"),
            library.appendingPathComponent("Preferences/\(bundleIdentifier).plist"),
            library.appendingPathComponent("Caches/\(bundleIdentifier)"),
            library.appendingPathComponent("Saved Application State/\(bundleIdentifier).savedState"),
            library.appendingPathComponent("HTTPStorages/\(bundleIdentifier)"),
            library.appendingPathComponent("Logs/\(supportFolderName)")
        ]
        let walker = FileTreeWalker()
        return candidates.compactMap { url in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
            let size: ByteCount = isDirectory.boolValue
                ? ((try? walker.measure(url).totalSize) ?? .zero)
                : ByteCount(Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0))
            return ScanItem(scanner: Self.scannerID, url: url, size: size, confidence: .medium)
        }
    }

    // MARK: Registrations

    /// What was registered with macOS and must be undone, besides files.
    public enum Registration: Sendable, Equatable {
        case helper
        case loginItem
    }

    public enum UnregisterError: Error, Sendable, Equatable {
        case failed(String)
    }

    /// Removes the privileged helper from launchd and the app from the login items. Each is a
    /// no-op when it was never registered.
    public static func unregister() async -> [Registration: UnregisterError?] {
        var result: [Registration: UnregisterError?] = [:]
        let helper = SMAppService.daemon(plistName: HelperIdentity.launchDaemonPlist)
        result[.helper] = await attempt { try await helper.unregister() }
        result[.loginItem] = await attempt { try await SMAppService.mainApp.unregister() }
        return result
    }

    private static func attempt(_ work: () async throws -> Void) async -> UnregisterError? {
        do {
            try await work()
            return nil
        } catch {
            // "Not registered" is the normal case and not a failure worth showing.
            let nsError = error as NSError
            if nsError.domain == "SMAppServiceErrorDomain", nsError.code == 1 || nsError.code == 3 { return nil }
            return .failed(error.localizedDescription)
        }
    }
}
