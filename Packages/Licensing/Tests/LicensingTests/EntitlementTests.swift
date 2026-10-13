import Testing
import Foundation
@testable import Licensing

@Suite("Free/Pro split")
struct FeatureSplitTests {
    @Test("Every feature is classified exactly once")
    func partitionIsComplete() {
        #expect(Feature.free.count + Feature.pro.count == Feature.allCases.count)
        #expect(Set(Feature.free).isDisjoint(with: Set(Feature.pro)))
    }

    @Test("Safety and transparency features are free — CLAUDE.md §11.3")
    func safetyIsNeverPaywalled() {
        #expect(!Feature.safetyAndTransparency.requiresPro)
        #expect(!Feature.malwareScanReport.requiresPro)
        #expect(!Feature.dashboard.requiresPro)
        #expect(!Feature.liveSystemMetrics.requiresPro)
    }

    @Test("Heavy scanners and the uninstaller are Pro")
    func proSetIsAsSpecified() {
        #expect(Feature.heavyScanners.requiresPro)
        #expect(Feature.appUninstaller.requiresPro)
        #expect(Feature.smartScan.requiresPro)
    }
}

@Suite("Entitlement gating")
struct EntitlementGatingTests {
    private let states: [LicenseState] = [
        .trial(daysRemaining: 14),
        .trial(daysRemaining: 0),
        .licensed(updatesUntil: .distantFuture),
        .updatesLapsed,
        .trialExpired
    ]

    @Test("Free features stay available in every licence state — §10.6")
    func freeFeaturesAlwaysAvailable() {
        for state in states {
            let resolver = StaticEntitlements(state)
            for feature in Feature.free {
                #expect(
                    resolver.isAvailable(feature),
                    "\(feature) must stay free in state \(state)"
                )
            }
        }
    }

    @Test("An expired trial locks Pro features but nothing else")
    func expiredTrialLocksOnlyPro() {
        let resolver = StaticEntitlements(.trialExpired)
        #expect(!resolver.state.unlocksPro)
        #expect(Set(resolver.lockedFeatures()) == Set(Feature.pro))
    }

    @Test("A lapsed update window keeps Pro unlocked and only stops updates — §11.3")
    func lapsedUpdatesKeepProUnlocked() {
        let resolver = StaticEntitlements(.updatesLapsed)
        #expect(resolver.state.unlocksPro)
        #expect(!resolver.state.receivesUpdates)
        #expect(resolver.lockedFeatures().isEmpty)
    }

    @Test("Trial unlocks everything and receives updates")
    func trialUnlocksEverything() {
        let resolver = StaticEntitlements(.trial(daysRemaining: 3))
        #expect(resolver.lockedFeatures().isEmpty)
        #expect(resolver.state.receivesUpdates)
    }

    @Test("Phase 1 stub unlocks everything")
    func stubUnlocksEverything() {
        let resolver = AlwaysProEntitlements()
        #expect(resolver.lockedFeatures().isEmpty)
        for feature in Feature.allCases {
            #expect(resolver.isAvailable(feature))
        }
    }
}

import CryptoKit

@Suite("Licence files")
struct LicenseFileTests {
    private let key = Curve25519.Signing.PrivateKey()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func payload(updatesUntil: Date? = nil, product: String = "burnish") -> LicensePayload {
        LicensePayload(
            licenseID: "L-1", email: "a@b.c", product: product,
            updatesUntil: updatesUntil ?? now.addingTimeInterval(86_400 * 365), deviceLimit: 1, issuedAt: now
        )
    }

    @Test("A signed licence verifies and round-trips")
    func roundTrip() throws {
        let text = try LicenseFile.sign(payload(), with: key)
        let read = try LicenseFile.verify(text, publicKey: key.publicKey, expectedProduct: "burnish")
        #expect(read == payload())
    }

    @Test("A licence signed by another key is refused")
    func wrongKey() throws {
        let text = try LicenseFile.sign(payload(), with: Curve25519.Signing.PrivateKey())
        #expect(throws: LicenseFile.Failure.badSignature) { try LicenseFile.verify(text, publicKey: key.publicKey, expectedProduct: "burnish") }
    }

    @Test("A licence edited after signing is refused")
    func tampered() throws {
        let text = try LicenseFile.sign(payload(), with: key)
        let parts = text.split(separator: ".").map(String.init)
        let forged = try LicenseFile.sign(payload(updatesUntil: now.addingTimeInterval(86_400 * 9_999)), with: Curve25519.Signing.PrivateKey())
        let forgedPayload = forged.split(separator: ".").map(String.init)[0]
        #expect(throws: LicenseFile.Failure.badSignature) {
            try LicenseFile.verify("\(forgedPayload).\(parts[1])", publicKey: key.publicKey, expectedProduct: "burnish")
        }
    }

    @Test("Garbage and a licence for another product are refused")
    func malformedAndProduct() throws {
        for bad in ["", "abc", "a.b.c", "....", "not base64!.not base64!"] {
            #expect(throws: LicenseFile.Failure.malformed) { try LicenseFile.verify(bad, publicKey: key.publicKey, expectedProduct: "burnish") }
        }
        let other = try LicenseFile.sign(payload(product: "other"), with: key)
        #expect(throws: LicenseFile.Failure.wrongProduct) { try LicenseFile.verify(other, publicKey: key.publicKey, expectedProduct: "burnish") }
    }

    @Test("Whitespace around a pasted licence is tolerated")
    func whitespace() throws {
        let text = try LicenseFile.sign(payload(), with: key)
        #expect((try? LicenseFile.verify("  \(text)\n", publicKey: key.publicKey, expectedProduct: "burnish")) != nil)
    }
}

@Suite("Trial")
struct TrialTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("The trial starts on first use with all 14 days")
    func starts() {
        let trial = Trial(store: InMemoryTrialStore())
        #expect(trial.daysRemaining(now: start) == 14)
    }

    @Test("Days count down and the trial ends after 14")
    func countsDown() {
        let trial = Trial(store: InMemoryTrialStore())
        _ = trial.daysRemaining(now: start)
        #expect(trial.daysRemaining(now: start.addingTimeInterval(86_400 * 5)) == 9)
        #expect(trial.daysRemaining(now: start.addingTimeInterval(86_400 * 13.5)) == 1)
        #expect(trial.daysRemaining(now: start.addingTimeInterval(86_400 * 14)) == nil)
    }

    @Test("Winding the clock back does not give time back")
    func clockRollback() {
        let trial = Trial(store: InMemoryTrialStore())
        _ = trial.daysRemaining(now: start)
        _ = trial.daysRemaining(now: start.addingTimeInterval(86_400 * 10))
        #expect(trial.daysRemaining(now: start) == 4, "still 4 days left, not 14")
    }

    @Test("A clock set far ahead only shortens the trial; it cannot break anything")
    func clockAhead() {
        let trial = Trial(store: InMemoryTrialStore())
        _ = trial.daysRemaining(now: start)
        #expect(trial.daysRemaining(now: start.addingTimeInterval(86_400 * 400)) == nil)
    }

    @Test("The file store keeps the trial across launches")
    func filePersistence() throws {
        let url = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishTrial-\(UUID().uuidString)/trial.json")
        defer {
            // Fixture teardown, not product code.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        _ = Trial(store: FileTrialStore(url: url)).daysRemaining(now: start)
        #expect(Trial(store: FileTrialStore(url: url)).daysRemaining(now: start.addingTimeInterval(86_400 * 2)) == 12)
    }
}

@Suite("Licence manager")
struct LicenseManagerTests {
    private let key = Curve25519.Signing.PrivateKey()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func licence(updatesUntil: Date) throws -> String {
        try LicenseFile.sign(
            LicensePayload(licenseID: "L", email: "a@b.c", product: "burnish", updatesUntil: updatesUntil, deviceLimit: 1, issuedAt: now), with: key
        )
    }

    private func manager(_ text: String?, publicKey: Curve25519.Signing.PublicKey?, at date: Date) -> LicenseManager {
        LicenseManager(licenseText: text, publicKey: publicKey, product: "burnish", trial: Trial(store: InMemoryTrialStore()), now: date)
    }

    @Test("No licence means the trial")
    func trial() {
        #expect(manager(nil, publicKey: key.publicKey, at: now).state == .trial(daysRemaining: 14))
    }

    @Test("A valid licence unlocks Pro and reports its update window")
    func licensed() throws {
        let until = now.addingTimeInterval(86_400 * 200)
        let result = manager(try licence(updatesUntil: until), publicKey: key.publicKey, at: now)
        #expect(result.state == .licensed(updatesUntil: until))
        #expect(result.isAvailable(.smartScan))
    }

    @Test("After the update window, Pro features stay open and only updates stop (§11.3)")
    func updatesLapsed() throws {
        let result = manager(try licence(updatesUntil: now.addingTimeInterval(-86_400)), publicKey: key.publicKey, at: now)
        #expect(result.state == .updatesLapsed)
        #expect(result.isAvailable(.smartScan))
        #expect(!result.state.receivesUpdates)
    }

    @Test("An invalid licence falls back to the trial instead of locking anything")
    func invalidFallsBack() {
        #expect(manager("garbage", publicKey: key.publicKey, at: now).state == .trial(daysRemaining: 14))
    }

    @Test("With no public key configured, a licence cannot be accepted, and free features stay free")
    func noKey() throws {
        let text = try licence(updatesUntil: now.addingTimeInterval(86_400))
        #expect(manager(text, publicKey: nil, at: now).state == .trial(daysRemaining: 14))
    }

    @Test("An expired trial locks Pro but never the free features")
    func expiredTrial() {
        let store = InMemoryTrialStore(TrialRecord(startedAt: now.addingTimeInterval(-86_400 * 30), lastSeen: now.addingTimeInterval(-86_400 * 30)))
        let result = LicenseManager(licenseText: nil, publicKey: key.publicKey, product: "burnish", trial: Trial(store: store), now: now)
        #expect(result.state == .trialExpired)
        #expect(!result.isAvailable(.smartScan))
        for feature in Feature.free { #expect(result.isAvailable(feature)) }
    }
}
