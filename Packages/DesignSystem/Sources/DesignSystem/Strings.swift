import Foundation

/// Localized text owned by this package.
///
/// CLAUDE.md §15: no user-facing string is hardcoded in source. Keys resolve against this
/// package's own String Catalog, so `DesignSystem` stays self-contained and the app does not
/// have to re-declare the strings its shared components need.
enum Strings {
    static let ringIndeterminate = LocalizedStringResource(
        "designsystem.ring.indeterminate",
        bundle: .atURL(Bundle.module.bundleURL)
    )

    static let emptyStateDefaultTitle = LocalizedStringResource(
        "designsystem.emptystate.default.title",
        bundle: .atURL(Bundle.module.bundleURL)
    )

    static let scanButtonHint = LocalizedStringResource(
        "designsystem.scanbutton.accessibility.hint",
        bundle: .atURL(Bundle.module.bundleURL)
    )

    static let proBadge = LocalizedStringResource(
        "designsystem.pro.badge",
        bundle: .atURL(Bundle.module.bundleURL)
    )
}
