import Foundation
import os

/// Logger factory.
///
/// CLAUDE.md §2: subsystem is the bundle identifier, category is the module name. Using this
/// instead of `print` keeps diagnostics out of release output and off the user's disk.
public enum Log {
    /// Returns a logger for a module, e.g. `Log.module("ScanEngine")`.
    public static func module(_ name: String) -> Logger {
        Logger(subsystem: AppIdentity.current.bundleIdentifier, category: name)
    }
}
