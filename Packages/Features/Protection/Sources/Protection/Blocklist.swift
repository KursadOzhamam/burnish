import Foundation
import CryptoKit

/// A list of SHA-256 hashes of files known to be malicious (CLAUDE.md §6.4).
///
/// The list is a signed document: Burnish only trusts one whose Ed25519 signature verifies
/// against the public key built into the app, so a tampered or substituted list is refused
/// rather than used. Matching is exact: a file is "known bad" only if its whole-content hash is
/// on the list, which is why this produces no false positives of the kind a heuristic does.
public struct Blocklist: Sendable {
    public struct Entry: Codable, Sendable, Equatable {
        public let sha256: String
        public let name: String

        public init(sha256: String, name: String) {
            self.sha256 = sha256.lowercased()
            self.name = name
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
        byHash = Dictionary(manifest.entries.map { ($0.sha256, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    public static let empty = Blocklist(manifest: Manifest(version: 0, entries: []))

    public var count: Int { byHash.count }

    /// The name recorded for `hash`, if it is on the list.
    public func name(forHash hash: String) -> String? { byHash[hash.lowercased()] }

    /// Reads a signed list. `payload` is the JSON of a `Manifest`; `signature` is the Ed25519
    /// signature over exactly those bytes.
    public static func load(payload: Data, signature: Data, publicKey: Curve25519.Signing.PublicKey) throws -> Blocklist {
        guard publicKey.isValidSignature(signature, for: payload) else { throw LoadError.badSignature }
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: payload) else { throw LoadError.malformed }
        return Blocklist(manifest: manifest)
    }
}

/// Streaming SHA-256 of a file, so a large file is never held in memory (CLAUDE.md §8).
public enum FileHasher {
    public static func sha256(of url: URL, chunkSize: Int = 1_024 * 1_024) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            let chunk = try autoreleasepool { try handle.read(upToCount: chunkSize) ?? Data() }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
