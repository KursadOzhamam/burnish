import Foundation

/// Names shared by the app and the helper.
public enum HelperIdentity {
    public static let machServiceName = "com.burnish.app.helper"
    public static let launchDaemonPlist = "com.burnish.app.helper.plist"
    public static let appIdentifier = "com.burnish.app"
    public static let protocolVersion = 1
}

/// The XPC interface. Plain Foundation types only, so it crosses the process boundary safely.
@objc public protocol HelperXPC {
    /// The helper's protocol version, so an old helper after an app update is noticed.
    func protocolVersion(reply: @escaping (Int) -> Void)

    /// Runs one of the fixed maintenance commands, named by `HelperCommand.rawValue`.
    func runCommand(_ rawValue: String, reply: @escaping (Int32, String) -> Void)

    /// Removes items in a system folder the helper is allowed to clean, after applying the
    /// safety policy itself. `paths` are absolute. The reply lists a failure message per path
    /// that was refused or failed; an empty list means everything went.
    func removeSystemItems(_ paths: [String], reply: @escaping ([String]) -> Void)
}
