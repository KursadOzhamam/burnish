import Foundation
import Security
import CoreKitMac

/// Reads what macOS's own defences say about the Mac and about a file (CLAUDE.md §6.4).
/// Reads only: Burnish complements XProtect and Gatekeeper, it does not replace them.
public struct AppleDefense: Sendable {
    public enum SignatureState: Sendable, Equatable {
        /// A valid signature.
        case valid
        /// Signed, but the signature does not check out: the bundle was changed after signing.
        case invalid
        case unsigned
    }

    private let runner: any CommandRunning

    public init(runner: any CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    // MARK: Per file

    /// Whether the code at `url` (an app bundle or a binary) has a valid signature.
    public static func signatureState(of url: URL) -> SignatureState {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return .unsigned }
        let status = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil)
        switch status {
        case errSecSuccess: return .valid
        case errSecCSUnsigned: return .unsigned
        default: return .invalid
        }
    }

    /// Whether the file carries the quarantine attribute, i.e. it came from the internet or a
    /// download and Gatekeeper has not yet cleared it.
    public static func isQuarantined(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    // MARK: Per Mac

    public struct SystemStatus: Sendable, Equatable {
        /// `true`, `false`, or nil when it could not be determined.
        public let gatekeeperEnabled: Bool?
        public let xprotectVersion: String?
        public let sipEnabled: Bool?
    }

    public func systemStatus() async -> SystemStatus {
        async let gatekeeper = Self.parseEnabled(try? await runner.run("/usr/sbin/spctl", arguments: ["--status"]), enabledWord: "enabled")
        async let sip = Self.parseEnabled(try? await runner.run("/usr/bin/csrutil", arguments: ["status"]), enabledWord: "enabled")
        return SystemStatus(
            gatekeeperEnabled: await gatekeeper,
            xprotectVersion: Self.xprotectVersion(),
            sipEnabled: await sip
        )
    }

    static func parseEnabled(_ result: CommandResult?, enabledWord: String) -> Bool? {
        guard let result, result.succeeded else { return nil }
        let text = result.output.lowercased()
        if text.contains("disabled") { return false }
        return text.contains(enabledWord) ? true : nil
    }

    static func xprotectVersion() -> String? {
        let candidates = [
            "/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist",
            "/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist"
        ]
        for path in candidates {
            if let info = NSDictionary(contentsOfFile: path), let version = info["CFBundleShortVersionString"] as? String { return version }
        }
        return nil
    }
}
