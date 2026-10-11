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
