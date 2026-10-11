import Foundation

/// The current licence situation.
///
/// CLAUDE.md §11.2: validation is entirely offline, so this is derived from a locally stored,
/// signed licence and never from a network call. The app must keep working without a network.
public enum LicenseState: Sendable, Hashable {
    /// Trial running, with whole days left (§11.3: 14 days, no card required).
    case trial(daysRemaining: Int)

    /// A valid licence. `updatesUntil` is when the included year of updates ends.
    case licensed(updatesUntil: Date)

    /// Trial finished and no licence present.
    case trialExpired

    /// Licence valid but its update window has passed.
    ///
    /// CLAUDE.md §11.3: the app keeps working and Pro features stay unlocked; only new version
    /// updates stop. This case exists so the updater can be disabled without touching features.
    case updatesLapsed

    /// Whether Pro features are unlocked right now.
    public var unlocksPro: Bool {
        switch self {
        case .trial, .licensed, .updatesLapsed: true
        case .trialExpired: false
        }
    }

    /// Whether the app should offer Sparkle updates.
    public var receivesUpdates: Bool {
        switch self {
        case .trial, .licensed: true
        case .trialExpired, .updatesLapsed: false
        }
    }
}

/// Resolves what the user may do.
public protocol EntitlementResolving: Sendable {
    var state: LicenseState { get }
}

extension EntitlementResolving {
    /// The single decision point for gating.
    ///
    /// Free features return `true` in **every** state — including an expired trial. See the
    /// test suite: this is the invariant that enforces §10.6 (the user's data is never held
    /// hostage) and the §11.3 promise that results stay visible after the trial ends.
    public func isAvailable(_ feature: Feature) -> Bool {
        guard feature.requiresPro else { return true }
        return state.unlocksPro
    }

    /// Features the user cannot currently reach, for the upgrade card (`ProGate`, §5.4).
    public func lockedFeatures() -> [Feature] {
        Feature.allCases.filter { !isAvailable($0) }
    }
}

/// Phase 1 stub: everything unlocked.
///
/// Real validation arrives in Phase 10 (CLAUDE.md §14). Existing now so that Pro gates are wired
/// into the right places from the start rather than retrofitted.
public struct AlwaysProEntitlements: EntitlementResolving {
    public let state: LicenseState

    public init(state: LicenseState = .licensed(updatesUntil: .distantFuture)) {
        self.state = state
    }
}

/// Fixed resolver used in tests and previews.
public struct StaticEntitlements: EntitlementResolving {
    public let state: LicenseState

    public init(_ state: LicenseState) {
        self.state = state
    }
}
