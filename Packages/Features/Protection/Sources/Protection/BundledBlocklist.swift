import Foundation
import CryptoKit

/// The known-bad hash list that ships inside the app (CLAUDE.md §6.4).
///
/// `Tools/BlocklistBuilder` produces two resources: `blocklist.json`, the `Blocklist.Manifest`
/// payload, and `blocklist.sig`, the Ed25519 signature over exactly those bytes. Nothing is fetched
/// at run time; Burnish stays offline (§10.7). A list whose signature does not verify against the
/// key below is not used at all, so a tampered resource can only make the list empty, never wrong.
public enum BlocklistConfiguration {
    /// Base64 of the raw Ed25519 public key that signs the list, printed by `BlocklistBuilder keygen`.
    /// The private half lives outside the repository, in ~/.config/burnish/blocklist-signing.key.
    static let publicKeyBase64 = "V/S/L3fwVvqXLbvTBAvMXBAUvSxK5z2dTCaIXbIsxaM="

    public static var publicKey: Curve25519.Signing.PublicKey? {
        guard let raw = Data(base64Encoded: publicKeyBase64) else { return nil }
        return try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
    }

    static let payloadName = "blocklist"
    static let payloadExtension = "json"
    static let signatureExtension = "sig"
}

extension Blocklist {
    /// The list bundled with this build, or `.empty` when there is none, no key is configured, or
    /// the signature does not verify.
    public static func bundled(
        bundle: Bundle? = nil,
        publicKey: Curve25519.Signing.PublicKey? = BlocklistConfiguration.publicKey
    ) -> Blocklist {
        let bundle = bundle ?? .module
        guard let publicKey,
              let payloadURL = bundle.url(
                forResource: BlocklistConfiguration.payloadName, withExtension: BlocklistConfiguration.payloadExtension
              ),
              let signatureURL = bundle.url(
                forResource: BlocklistConfiguration.payloadName, withExtension: BlocklistConfiguration.signatureExtension
              ),
              let payload = try? Data(contentsOf: payloadURL),
              let signature = try? Data(contentsOf: signatureURL),
              let list = try? load(payload: payload, signature: signature, publicKey: publicKey)
        else { return .empty }
        return list
    }
}
