import Testing
import Foundation
import CryptoKit
@testable import Licensing

@Suite("Licence activation")
struct LicenseActivationTests {
    private let key = Curve25519.Signing.PrivateKey()

    private func licence(product: String = "burnish", signedWith signer: Curve25519.Signing.PrivateKey? = nil) throws -> String {
        let payload = LicensePayload(
            licenseID: "L-1", email: "user@example.com", product: product,
            updatesUntil: Date(timeIntervalSinceNow: 86_400 * 365), deviceLimit: 1, issuedAt: Date()
        )
        return try LicenseFile.sign(payload, with: signer ?? key)
    }

    @Test("A valid licence is accepted, stored and read back")
    func activates() throws {
        let store = InMemoryLicenseStore()
        let activation = LicenseActivation(store: store, publicKey: key.publicKey)
        let text = try licence()

        let result = activation.activate("  \(text)\n")
        #expect(try result.get().email == "user@example.com")
        #expect(store.load() == text)
        #expect(activation.current()?.licenseID == "L-1")
    }

    @Test("Without a built-in key nothing is accepted, and the app can say why")
    func notConfigured() throws {
        let store = InMemoryLicenseStore()
        let activation = LicenseActivation(store: store, publicKey: nil)
        #expect(!activation.isConfigured)
        #expect(activation.activate(try licence()) == .failure(.notConfigured))
        #expect(store.load() == nil)
    }

    @Test("Invalid licences are refused and never stored")
    func refusals() throws {
        let store = InMemoryLicenseStore()
        let activation = LicenseActivation(store: store, publicKey: key.publicKey)
        #expect(activation.activate("   ") == .failure(.empty))
        #expect(activation.activate("not-a-licence") == .failure(.malformed))
        #expect(activation.activate(try licence(signedWith: Curve25519.Signing.PrivateKey())) == .failure(.badSignature))
        #expect(activation.activate(try licence(product: "other")) == .failure(.wrongProduct))
        #expect(store.load() == nil)
    }

    @Test("Deactivating forgets the licence")
    func deactivates() throws {
        let store = InMemoryLicenseStore()
        let activation = LicenseActivation(store: store, publicKey: key.publicKey)
        _ = activation.activate(try licence())
        activation.deactivate()
        #expect(activation.current() == nil)
    }

    @Test("A stored licence that no longer verifies is not reported as current")
    func tamperedStore() throws {
        let store = InMemoryLicenseStore(try licence(signedWith: Curve25519.Signing.PrivateKey()))
        #expect(LicenseActivation(store: store, publicKey: key.publicKey).current() == nil)
    }

    @Test("The product name matches what the licence tool signs")
    func productName() {
        #expect(LicenseConfiguration.product == "burnish")
    }
}
