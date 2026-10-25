import Foundation
import CryptoKit

/// What the app is built to accept (CLAUDE.md §11.2).
public enum LicenseConfiguration {
    /// The product name every licence must carry; `Tools/LicenseTool` signs with the same value.
    public static let product = "burnish"

    /// The public half of the signing key, built into the app.
    ///
    /// Nil until the production key pair exists (Phase 10, §14): with no key no licence can be
    /// accepted, and the app says so instead of pretending to check. Set it from the `PUBLIC` line
    /// `LicenseTool keygen` prints.
    public static let publicKey: Curve25519.Signing.PublicKey? = nil
}

/// Where the entered licence text is kept. The app uses the Keychain; tests use memory.
public protocol LicenseStoring: Sendable {
    func load() -> String?
    func save(_ text: String)
    func clear()
}

public final class InMemoryLicenseStore: LicenseStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var text: String?

    public init(_ text: String? = nil) { self.text = text }
    public func load() -> String? { lock.withLock { text } }
    public func save(_ text: String) { lock.withLock { self.text = text } }
    public func clear() { lock.withLock { text = nil } }
}

/// Entering, checking and removing a licence, offline (CLAUDE.md §11.2).
///
/// A licence is stored only after it verifies, so what is stored is always something the app
/// accepted. Nothing here touches the network.
public struct LicenseActivation: Sendable {
    public enum Failure: Error, Sendable, Equatable {
        /// This build has no public key yet, so no licence can be checked.
        case notConfigured
        case empty
        case malformed
        case badSignature
        case wrongProduct
    }

    private let store: any LicenseStoring
    private let publicKey: Curve25519.Signing.PublicKey?
    private let product: String

    public init(
        store: any LicenseStoring,
        publicKey: Curve25519.Signing.PublicKey? = LicenseConfiguration.publicKey,
        product: String = LicenseConfiguration.product
    ) {
        self.store = store
        self.publicKey = publicKey
        self.product = product
    }

    /// Whether this build can verify licences at all.
    public var isConfigured: Bool { publicKey != nil }

    /// The stored licence, if it still verifies.
    public func current() -> LicensePayload? {
        guard let text = store.load(), let publicKey else { return nil }
        return try? LicenseFile.verify(text, publicKey: publicKey, expectedProduct: product)
    }

    /// Verifies `text` and, only if it is valid, stores it.
    public func activate(_ text: String) -> Result<LicensePayload, Failure> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard let publicKey else { return .failure(.notConfigured) }
        do {
            let payload = try LicenseFile.verify(trimmed, publicKey: publicKey, expectedProduct: product)
            store.save(trimmed)
            return .success(payload)
        } catch let failure as LicenseFile.Failure {
            switch failure {
            case .malformed: return .failure(.malformed)
            case .badSignature: return .failure(.badSignature)
            case .wrongProduct: return .failure(.wrongProduct)
            }
        } catch {
            return .failure(.malformed)
        }
    }

    /// Forgets the licence on this Mac. The purchase itself is unaffected.
    public func deactivate() { store.clear() }
}
