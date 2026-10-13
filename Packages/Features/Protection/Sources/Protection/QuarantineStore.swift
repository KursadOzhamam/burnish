import Foundation

/// Where suspicious items wait (CLAUDE.md §6.4): moved, never deleted, and restorable.
///
/// Each item gets its own folder holding the moved file and a small record of where it came
/// from. The folder lives in Burnish's own support directory, which the safety layer protects
/// from every removal path (§4.3), so nothing in the app can delete from it by accident.
public struct QuarantineStore: Sendable {
    public struct Record: Codable, Sendable, Identifiable, Equatable {
        public let id: UUID
        public let originalPath: String
        public let storedName: String
        public let date: Date
        public let reason: String
    }

    public enum QuarantineError: Error, Sendable, Equatable {
        case sourceMissing
        case destinationOccupied
        case notFound
        case failed(String)
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private func folder(for id: UUID) -> URL { directory.appendingPathComponent(id.uuidString, isDirectory: true) }

    // MARK: Quarantine

    /// Moves `url` into quarantine. The original is gone from its place until restored.
    @discardableResult
    public func quarantine(_ url: URL, reason: String, now: Date = Date()) throws -> Record {
        guard FileManager.default.fileExists(atPath: url.path) else { throw QuarantineError.sourceMissing }
        let id = UUID()
        let record = Record(id: id, originalPath: url.path, storedName: url.lastPathComponent, date: now, reason: reason)
        let target = folder(for: id)
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: target.appendingPathComponent(record.storedName))
            try JSONEncoder().encode(record).write(to: target.appendingPathComponent("record.json"))
            // Nothing in quarantine may be executed by accident.
            let stored = target.appendingPathComponent(record.storedName)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stored.path)
        } catch {
            throw QuarantineError.failed(error.localizedDescription)
        }
        return record
    }

    // MARK: List and restore

    public func records() -> [Record] {
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return folders.compactMap { folder in
            (try? Data(contentsOf: folder.appendingPathComponent("record.json"))).flatMap { try? JSONDecoder().decode(Record.self, from: $0) }
        }
        .sorted { $0.date > $1.date }
    }

    /// Puts the item back exactly where it came from. Refuses to overwrite anything now there.
    public func restore(_ record: Record) throws {
        let stored = folder(for: record.id).appendingPathComponent(record.storedName)
        guard FileManager.default.fileExists(atPath: stored.path) else { throw QuarantineError.notFound }
        let destination = URL(fileURLWithPath: record.originalPath)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw QuarantineError.destinationOccupied }
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: stored, to: destination)
            // The folder only held the item and its record.
            try? FileManager.default.moveItem(at: folder(for: record.id), to: Self.leftoverSlot(in: directory, id: record.id))
        } catch {
            throw QuarantineError.failed(error.localizedDescription)
        }
    }

    /// An emptied record folder is renamed out of the listing rather than deleted: this type
    /// never removes anything (CLAUDE.md §4: all removal goes through the safety layer).
    private static func leftoverSlot(in directory: URL, id: UUID) -> URL {
        directory.appendingPathComponent(".restored-\(id.uuidString)")
    }
}
