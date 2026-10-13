import Foundation
import CryptoKit

/// What a purchased licence says (CLAUDE.md §11.2).
public struct LicensePayload: Codable, Sendable, Equatable {
    public let licenseID: String
    public let email: String
    public let product: String
    /// Updates are included until this date; the app keeps working after it.
    public let updatesUntil: Date
    public let deviceLimit: Int
    public let issuedAt: Date

    public init(licenseID: String, email: String, product: String, updatesUntil: Date, deviceLimit: Int, issuedAt: Date) {
        self.licenseID = licenseID
        self.email = email
        self.product = product
        self.updatesUntil = updatesUntil
        self.deviceLimit = deviceLimit
        self.issuedAt = issuedAt
    }
}

/// A licence is `base64url(payload JSON) "." base64url(Ed25519 signature over those bytes)`.
///
/// Verification is entirely local and offline: the public key is built into the app and nothing
/// here touches the network (§11.2, §10.7).
public enum LicenseFile {
    public enum Failure: Error, Sendable, Equatable {
        case malformed
        case badSignature
        case wrongProduct
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Produces a licence string. Used by the licence tool and by tests, never by the app.
    public static func sign(_ payload: LicensePayload, with key: Curve25519.Signing.PrivateKey) throws -> String {
        let data = try encoder.encode(payload)
        let signature = try key.signature(for: data)
        return "\(base64url(data)).\(base64url(signature))"
    }

    /// Reads and verifies a licence string.
    public static func verify(
        _ text: String, publicKey: Curve25519.Signing.PublicKey, expectedProduct: String
    ) throws -> LicensePayload {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let data = decode(String(parts[0])), let signature = decode(String(parts[1])) else {
            throw Failure.malformed
        }
        guard publicKey.isValidSignature(signature, for: data) else { throw Failure.badSignature }
        guard let payload = try? decoder.decode(LicensePayload.self, from: data) else { throw Failure.malformed }
        guard payload.product == expectedProduct else { throw Failure.wrongProduct }
        return payload
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        return Data(base64Encoded: base64)
    }
}
