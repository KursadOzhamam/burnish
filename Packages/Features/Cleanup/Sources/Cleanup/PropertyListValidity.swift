import Foundation

/// Decides whether a property list file is genuinely broken.
///
/// "Could not open" and "is corrupt" are different facts. A file the app lacks permission for
/// (Messages and Contacts preferences on a Mac without Full Disk Access) fails to open but is
/// perfectly healthy, so only a file that is read successfully and then fails to parse counts.
enum PropertyListValidity {
    enum Verdict: Equatable {
        case healthy
        case malformed
        /// Could not be read, so nothing can be said about it.
        case unknown
    }

    static func verdict(for url: URL) -> Verdict {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .unknown
        }
        if data.isEmpty { return .malformed }
        do {
            _ = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            return .healthy
        } catch {
            return .malformed
        }
    }
}
