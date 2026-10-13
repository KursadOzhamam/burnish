import Foundation
import IOKit

/// The Mac's marketing model and OS version, for page footers.
///
/// Reads `IODeviceTree:/product`, which carries the marketing name ("MacBook Pro (14-inch, Nov
/// 2024)"), and falls back to the hardware identifier rather than guessing: a wrong model name
/// would undermine trust in every other number on screen.
public enum MachineLabel {
    public static let model: String = {
        for key in ["product-name", "product-description"] {
            let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
            guard entry != 0 else { break }
            defer { IOObjectRelease(entry) }
            if let property = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
               let data = property as? Data,
               let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0")),
               !text.isEmpty {
                return text
            }
        }
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "Mac" }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "Mac" }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }()

    public static var system: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let short = version.patchVersion == 0 ? "\(version.majorVersion).\(version.minorVersion)"
                                              : "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        return "macOS \(short)"
    }
}
