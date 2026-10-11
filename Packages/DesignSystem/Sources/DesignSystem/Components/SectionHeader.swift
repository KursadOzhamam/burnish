import SwiftUI

/// Gradient section title and description — CLAUDE.md §5.4.
public struct SectionHeader: View {
    private let title: LocalizedStringResource
    private let subtitle: LocalizedStringResource?
    private let palette: GradientPair

    public init(
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource? = nil,
        palette: GradientPair
    ) {
        self.title = title
        self.subtitle = subtitle
        self.palette = palette
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(Typography.title)
                .foregroundStyle(palette.linear)

            if let subtitle {
                Text(subtitle)
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview("SectionHeader") {
    VStack(alignment: .leading, spacing: Spacing.xl) {
        ForEach(AppSection.allCases) { section in
            SectionHeader(
                title: .init(stringLiteral: section.rawValue.capitalized),
                subtitle: "A short description of what this area does.",
                palette: section.palette
            )
        }
    }
    .padding(Spacing.xl)
    .frame(width: 520)
}
