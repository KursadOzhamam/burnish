import Foundation
import CryptoKit

/// A list of hashes of files known to be malicious (CLAUDE.md §6.4).
///
/// Entries are SHA-1 (40 hex digits) or SHA-256 (64 hex digits), because public macOS malware
/// lists come in both. One dictionary holds them all: the two lengths cannot collide, and lookup
/// stays O(1) whatever the list's size.
///
/// The list is a signed document: Burnish only trusts one whose Ed25519 signature verifies
/// against the public key built into the app, so a tampered or substituted list is refused
/// rather than used. Matching is exact: a file is "known bad" only if its whole-content hash is
/// on the list, which is why this produces no false positives of the kind a heuristic does.
public struct Blocklist: Sendable {
    public struct Entry: Codable, Sendable, Equatable {
        /// Lowercase hex digest, SHA-1 or SHA-256.
        public let hash: String
        public let name: String

        public init(hash: String, name: String) {
            self.hash = hash.lowercased()
            self.name = name
        }

        /// The SHA-256 form, kept for the lists that only carry SHA-256.
        public init(sha256: String, name: String) {
            self.init(hash: sha256, name: name)
        }

        private enum CodingKeys: String, CodingKey { case hash, sha256, name }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Lists written before SHA-1 support named the field "sha256".
            let hash = try container.decodeIfPresent(String.self, forKey: .hash)
                ?? container.decode(String.self, forKey: .sha256)
            self.init(hash: hash, name: try container.decode(String.self, forKey: .name))
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(hash, forKey: .hash)
            try container.encode(name, forKey: .name)
        }
    }

    /// The signed payload.
    public struct Manifest: Codable, Sendable, Equatable {
        public let version: Int
        public let entries: [Entry]

        public init(version: Int, entries: [Entry]) {
            self.version = version
            self.entries = entries
        }
    }

    public enum LoadError: Error, Sendable, Equatable {
        case badSignature
        case malformed
    }

    public let version: Int
    private let byHash: [String: String]

    public init(manifest: Manifest) {
        version = manifest.version
        byHash = Dictionary(manifest.entries.map { ($0.hash, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    public static let empty = Blocklist(manifest: Manifest(version: 0, entries: []))

    public var count: Int { byHash.count }

    /// The name recorded for `hash`, if it is on the list.
    public func name(forHash hash: String) -> String? { byHash[hash.lowercased()] }

    /// The name recorded for a file, matched by either of its digests.
    public func name(for digests: FileDigests) -> String? {
        name(forHash: digests.sha1) ?? name(forHash: digests.sha256)
    }

    /// Reads a signed list. `payload` is the JSON of a `Manifest`; `signature` is the Ed25519
    /// signature over exactly those bytes.
    public static func load(payload: Data, signature: Data, publicKey: Curve25519.Signing.PublicKey) throws -> Blocklist {
        guard publicKey.isValidSignature(signature, for: payload) else { throw LoadError.badSignature }
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: payload) else { throw LoadError.malformed }
        return Blocklist(manifest: manifest)
    }
}

/// A file's SHA-1 and SHA-256, as lowercase hex.
public struct FileDigests: Sendable, Equatable {
    public let sha1: String
    public let sha256: String
}

/// Streaming hashes of a file, so a large file is never held in memory (CLAUDE.md §8).
public enum FileHasher {
    /// SHA-1 and SHA-256 together, from one read of the file.
    ///
    /// SHA-1 is here only to look a file up in lists published as SHA-1. It is broken for
    /// collision resistance, which matters little for a blocklist: a crafted collision could at
    /// worst make a harmless file look like a listed one (a false alarm the user can dismiss),
    /// never hide malware that is on the list.
    public static func digests(of url: URL, chunkSize: Int = 1_024 * 1_024) throws -> FileDigests {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var sha1 = Insecure.SHA1()
        var sha256 = SHA256()
        while true {
            try Task.checkCancellation()
            let chunk = try autoreleasepool { try handle.read(upToCount: chunkSize) ?? Data() }
            if chunk.isEmpty { break }
            sha1.update(data: chunk)
            sha256.update(data: chunk)
        }
        return FileDigests(sha1: hex(sha1.finalize()), sha256: hex(sha256.finalize()))
    }

    public static func sha256(of url: URL, chunkSize: Int = 1_024 * 1_024) throws -> String {
        try digests(of: url, chunkSize: chunkSize).sha256
    }

    public static func sha1(of url: URL, chunkSize: Int = 1_024 * 1_024) throws -> String {
        try digests(of: url, chunkSize: chunkSize).sha1
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
