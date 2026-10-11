import SwiftUI

/// Placeholder for an empty result list — CLAUDE.md §5.4.
///
/// Finding nothing is good news for the user, so the copy and colour stay calm: §10.3 forbids
/// dressing an ordinary state up as a problem.
public struct EmptyState: View {
    private let symbol: String
    private let title: LocalizedStringResource
    private let message: LocalizedStringResource?

    public init(
        symbol: String = "checkmark.circle",
        title: LocalizedStringResource? = nil,
        message: LocalizedStringResource? = nil
    ) {
        self.symbol = symbol
        self.title = title ?? Strings.emptyStateDefaultTitle
        self.message = message
    }

    public var body: some View {
        VStack(spacing: Spacing.small) {
            Image(systemName: symbol)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)

            Text(title)
                .font(Typography.cardTitle)

            if let message {
                Text(message)
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }
}

#Preview("EmptyState") {
    EmptyState(
        symbol: "sparkles",
        title: "Nothing to clean",
        message: "This Mac has no reclaimable cache right now. Try again after a few days of use."
    )
    .frame(width: 460, height: 320)
}
