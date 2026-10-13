import Foundation
import GRDB

/// Reads which apps hold privacy permissions (CLAUDE.md §6.4, §10.2).
///
/// **Read only.** The privacy database is opened read-only and nothing here can write to it;
/// changing a permission is the user's act in System Settings, which this view only points to.
public struct TCCReader: Sendable {
    public struct Entry: Identifiable, Sendable, Hashable {
        public enum Service: String, Sendable, CaseIterable {
            case camera = "kTCCServiceCamera"
            case microphone = "kTCCServiceMicrophone"
            case screenRecording = "kTCCServiceScreenCapture"
            case fullDiskAccess = "kTCCServiceSystemPolicyAllFiles"
            case accessibility = "kTCCServiceAccessibility"
            case inputMonitoring = "kTCCServiceListenEvent"
            case contacts = "kTCCServiceAddressBook"
            case photos = "kTCCServicePhotos"
            case location = "kTCCServiceLocation"
        }

        public let service: Service
        public let client: String
        public let isAllowed: Bool

        public var id: String { "\(service.rawValue)|\(client)" }
    }

    public enum ReadError: Error, Sendable, Equatable {
        /// Usually: Full Disk Access has not been granted to Burnish.
        case unreadable
    }

    public let databaseURL: URL

    public init(databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")) {
        self.databaseURL = databaseURL
    }

    public func entries() throws -> [Entry] {
        var configuration = Configuration()
        configuration.readonly = true
        let queue: DatabaseQueue
        do {
            queue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        } catch {
            throw ReadError.unreadable
        }
        let known = Dictionary(uniqueKeysWithValues: Entry.Service.allCases.map { ($0.rawValue, $0) })
        do {
            return try queue.read { database in
                let rows = try Row.fetchAll(database, sql: "SELECT service, client, auth_value FROM access")
                return rows.compactMap { row -> Entry? in
                    guard let service: String = row["service"], let match = known[service], let client: String = row["client"] else { return nil }
                    // auth_value: 0 denied, 2 allowed, 3 limited.
                    return Entry(service: match, client: client, isAllowed: (row["auth_value"] as Int? ?? 0) >= 2)
                }
            }
        } catch {
            throw ReadError.unreadable
        }
    }

    /// The Settings pane for a service, so the user can change it themselves.
    public static func settingsURL(for service: Entry.Service) -> URL? {
        let pane: String
        switch service {
        case .camera: pane = "Privacy_Camera"
        case .microphone: pane = "Privacy_Microphone"
        case .screenRecording: pane = "Privacy_ScreenCapture"
        case .fullDiskAccess: pane = "Privacy_AllFiles"
        case .accessibility: pane = "Privacy_Accessibility"
        case .inputMonitoring: pane = "Privacy_ListenEvent"
        case .contacts: pane = "Privacy_Contacts"
        case .photos: pane = "Privacy_Photos"
        case .location: pane = "Privacy_LocationServices"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
    }
}
