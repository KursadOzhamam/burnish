import SwiftUI
import CoreKit
import CoreKitMac
import DesignSystem

/// What a landing page says, so Cleanup and Privacy share one layout with their own words.
struct LandingContent {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let heroHeading: LocalizedStringResource
    let heroMessage: LocalizedStringResource
    let heroNote: LocalizedStringResource
    let heroSymbol: String
    let heroBadge: String
    let listHeading: LocalizedStringResource
    let infoSymbol: String
    let infoHeading: LocalizedStringResource
    let infoMessage: LocalizedStringResource
    let infoNote: LocalizedStringResource
    let infoButton: LocalizedStringResource?
    let footerNote: LocalizedStringResource
    let actionTitle: LocalizedStringResource
    /// Whether each row can be switched off (Cleanup) or is fixed (Privacy).
    let togglable: Bool

    static let cleanup = LandingContent(
        title: CleanupStrings.title,
        subtitle: CleanupStrings.key("cleanup.landing.subtitle"),
        heroHeading: CleanupStrings.key("cleanup.landing.hero.heading"),
        heroMessage: CleanupStrings.key("cleanup.landing.hero.message"),
        heroNote: CleanupStrings.key("cleanup.landing.hero.note"),
        heroSymbol: "magnifyingglass.circle", heroBadge: "sparkles",
        listHeading: CleanupStrings.key("cleanup.landing.list"),
        infoSymbol: "shield", infoHeading: CleanupStrings.key("cleanup.landing.info.heading"),
        infoMessage: CleanupStrings.key("cleanup.landing.info.message"),
        infoNote: CleanupStrings.key("cleanup.landing.info.note"),
        infoButton: CleanupStrings.key("cleanup.landing.info.button"),
        footerNote: CleanupStrings.key("cleanup.landing.footer"),
        actionTitle: CleanupStrings.key("cleanup.landing.action"),
        togglable: true
    )

    static let privacy = LandingContent(
        title: CleanupStrings.key("privacy.title"),
        subtitle: CleanupStrings.key("privacy.landing.subtitle"),
        heroHeading: CleanupStrings.key("privacy.landing.hero.heading"),
        heroMessage: CleanupStrings.key("privacy.landing.hero.message"),
        heroNote: CleanupStrings.key("privacy.landing.hero.note"),
        heroSymbol: "hand.raised", heroBadge: "lock",
        listHeading: CleanupStrings.key("privacy.landing.list"),
        infoSymbol: "info.circle", infoHeading: CleanupStrings.key("privacy.landing.info.heading"),
        infoMessage: CleanupStrings.key("privacy.landing.info.message"),
        infoNote: CleanupStrings.key("privacy.landing.info.note"),
        infoButton: nil,
        footerNote: CleanupStrings.key("privacy.landing.footer"),
        actionTitle: CleanupStrings.key("privacy.landing.action"),
        togglable: false
    )
}

/// The first screen of Cleanup and Privacy: what will be scanned, and one round button to start.
struct CleanupLanding: View {
    let model: CleanupModel
    let content: LandingContent
    let rules: [CleanupRule]
    let onChange: () -> Void

    @State private var preferences = ScannerPreferences()
    @State private var refresh = 0

    private func isOn(_ rule: CleanupRule) -> Bool {
        _ = refresh
        return content.togglable ? preferences.isEnabled(rule) : true
    }

    private var selectedCount: Int { rules.filter(isOn).count }

    private static let symbols: [String: String] = [
        "cleanup.userCaches": "internaldrive", "cleanup.userLogs": "doc.text", "cleanup.developerJunk": "hammer",
        "cleanup.browserCaches": "globe", "cleanup.mailDownloads": "envelope", "cleanup.mobileBackups": "iphone",
        "cleanup.userTrash": "trash", "cleanup.systemCaches": "gearshape", "cleanup.xcodeDeviceSupport": "shippingbox",
        "cleanup.xcodeArchives": "shippingbox", "cleanup.appCaches": "app.badge", "cleanup.adobeMediaCaches": "app.badge",
        "cleanup.brokenPreferences": "exclamationmark.triangle", "cleanup.downloads": "arrow.down.circle",
        "privacy.safari": "safari", "privacy.chromium": "globe", "privacy.recentItems": "clock.arrow.circlepath"
    ]

    private static func symbol(for rule: CleanupRule) -> String { symbols[rule.id.rawValue] ?? "square.dashed" }

    var body: some View {
        let byRow = rules.map { rule in (rule, FeatureRow(
            symbol: Self.symbol(for: rule), title: CleanupStrings.key(rule.titleKey), detail: CleanupStrings.key(rule.explanationKey),
            status: isOn(rule) ? CleanupStrings.key("cleanup.landing.included") : CleanupStrings.key("cleanup.landing.excluded"),
            highlightsStatus: isOn(rule)
        )) }
        let ruleByRow = Dictionary(uniqueKeysWithValues: byRow.map { ($0.1.id, $0.0) })

        SectionPage(
            title: content.title,
            subtitle: content.subtitle,
            footer: PageFooter(
                lastScan: String(localized: CleanupStrings.key("cleanup.landing.lastScan")),
                note: content.footerNote, machine: MachineLabel.model, system: MachineLabel.system
            ),
            actionTitle: content.actionTitle,
            action: model.scan
        ) {
            HeroCard(heading: content.heroHeading, message: content.heroMessage, note: content.heroNote) {
                StatusRing(symbol: content.heroSymbol, title: String(localized: CleanupStrings.key("cleanup.landing.notScanned")))
            } trailing: {
                IllustrationTile(symbol: content.heroSymbol, badge: content.heroBadge)
            }
        } content: {
            HStack(alignment: .top, spacing: 16) {
                FeatureListCard(
                    heading: content.listHeading,
                    trailingHeading: CleanupStrings.selectedCategories(selectedCount),
                    rows: byRow.map(\.1)
                ) { row in
                    if content.togglable, let rule = ruleByRow[row.id] {
                        BrandCheckbox(isOn: isOn(rule)) {
                            preferences.setEnabled(!isOn(rule), for: rule)
                            refresh += 1
                            onChange()
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                InfoCard(
                    symbol: content.infoSymbol, heading: content.infoHeading, message: content.infoMessage, note: content.infoNote,
                    buttonTitle: content.infoButton, action: content.infoButton == nil ? nil : { openSettings() }
                )
                .frame(width: 280)
            }
        }
    }

    /// The scanner switches live in Settings too; open it from here.
    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
