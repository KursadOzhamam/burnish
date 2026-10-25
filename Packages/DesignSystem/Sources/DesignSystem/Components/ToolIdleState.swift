import SwiftUI

/// The idle state of a heavy tool screen (large files, duplicates, Space Lens, the shredder): an
/// idle brand ring with the tool's symbol, a short prompt and the scan button.
///
/// It replaces a centred `EmptyState` whose title repeated the page header, which read as two
/// designs on one screen. This matches the hero ring on every landing page, so a tool screen and
/// the section it came from share one language (CLAUDE.md §5.1).
public struct ToolIdleState: View {
    @Environment(\.colorScheme) private var scheme

    private let symbol: String
    private let message: LocalizedStringResource
    private let actionTitle: LocalizedStringResource
    private let action: () -> Void

    public init(
        symbol: String,
        message: LocalizedStringResource,
        actionTitle: LocalizedStringResource,
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        let t = scheme.theme
        VStack(spacing: Spacing.large) {
            Spacer()
            StatusRing(symbol: symbol, title: "", diameter: 150)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(t.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            ScanButton(title: actionTitle, palette: Brand.pair, action: action)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
