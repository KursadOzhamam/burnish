import Foundation

/// A capability that may or may not require a licence.
///
/// Mirrors the table in CLAUDE.md §11.3. The governing rule is that **safety and transparency are
/// never paywalled**: dry-run, history, restore, the malware scan report and complete uninstall
/// stay free in every licence state, because putting trust behind a paywall would undo the
/// difference described in §1.
public enum Feature: String, Sendable, Codable, CaseIterable {
    // MARK: Free

    case dashboard
    case liveSystemMetrics
    case menuBarPanel
    case basicCleanup
    case malwareScanReport
    /// Dry-run, operation history, restore, complete uninstall (§4, §6.9).
    case safetyAndTransparency

    // MARK: Pro

    case smartScan
    /// Duplicate finder, similar photos, Space Lens (§6.7, all `.heavy`).
    case heavyScanners
    case appUninstaller
    case quarantineManagement
    case maintenanceTasks
    case startupItems
    case scheduledScans
    case privacyCleanup

    /// Whether this feature needs an active licence.
    ///
    /// Expressed as a property on the feature itself so the free/Pro split lives in one place
    /// and cannot drift between the UI and the entitlement check.
    public var requiresPro: Bool {
        switch self {
        case .dashboard, .liveSystemMetrics, .menuBarPanel, .basicCleanup,
             .malwareScanReport, .safetyAndTransparency:
            false
        case .smartScan, .heavyScanners, .appUninstaller, .quarantineManagement,
             .maintenanceTasks, .startupItems, .scheduledScans, .privacyCleanup:
            true
        }
    }

    public static var free: [Feature] { allCases.filter { !$0.requiresPro } }
    public static var pro: [Feature] { allCases.filter(\.requiresPro) }
}
