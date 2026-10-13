import Foundation
import CryptoKit

/// Decides the licence state from a licence string and the trial, offline (CLAUDE.md §11).
public struct LicenseManager: EntitlementResolving {
    public let state: LicenseState
    public let payload: LicensePayload?

    /// - Parameters:
    ///   - licenseText: what the user entered, if anything.
    ///   - publicKey: the key built into the app. Nil means none is configured yet, so no licence
    ///     can be accepted and only the trial applies.
    public init(
        licenseText: String?, publicKey: Curve25519.Signing.PublicKey?, product: String,
        trial: Trial, now: Date = Date()
    ) {
        if let text = licenseText, let key = publicKey,
           let payload = try? LicenseFile.verify(text, publicKey: key, expectedProduct: product) {
            self.payload = payload
            // After the update window the app keeps working with everything it already has (§11.3).
            state = now <= payload.updatesUntil ? .licensed(updatesUntil: payload.updatesUntil) : .updatesLapsed
            return
        }
        payload = nil
        if let days = trial.daysRemaining(now: now) {
            state = .trial(daysRemaining: days)
        } else {
            state = .trialExpired
        }
    }
}
