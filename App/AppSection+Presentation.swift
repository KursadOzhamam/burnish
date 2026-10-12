import SwiftUI
import DesignSystem

/// Sidebar presentation for the sections defined in `DesignSystem`.
///
/// The enum and its palette live in DesignSystem so colour and section can never drift apart
/// (CLAUDE.md §5.3); the localized labels belong to the app, which owns the String Catalog.
///
/// Exposed as `LocalizedStringResource` rather than `LocalizedStringKey` because the shared
/// components take resources, and a resource can be passed on without being re-wrapped.
extension AppSection {
    var title: LocalizedStringResource {
        switch self {
        case .dashboard: "sidebar.dashboard"
        case .smartScan: "sidebar.smartScan"
        case .cleanup: "sidebar.cleanup"
        case .protection: "sidebar.protection"
        case .performance: "sidebar.performance"
        case .applications: "sidebar.applications"
        case .files: "sidebar.files"
        case .privacy: "sidebar.privacy"
        }
    }

    /// Whether Phase 1 has a real screen for this section.
    var isImplemented: Bool {
        switch self {
        case .dashboard, .smartScan, .cleanup: true
        case .protection, .performance, .applications, .files, .privacy: false
        }
    }
}
