import SwiftUI

/// Icon + title + value + optional trend — CLAUDE.md §5.4.
///
/// The dashboard grid is built from these (§6.1).
public struct MetricTile: View {
    private let symbol: String
    private let title: LocalizedStringResource
    private let value: String
    private let detail: LocalizedStringResource?
    private let palette: GradientPair
    private let trend: [Double]

    public init(
        symbol: String,
        title: LocalizedStringResource,
        value: String,
        detail: LocalizedStringResource? = nil,
        palette: GradientPair,
        trend: [Double] = []
    ) {
        self.symbol = symbol
        self.title = title
        self.value = value
        self.detail = detail
        self.palette = palette
        self.trend = trend
    }

    public var body: some View {
        GlassCard(isInteractive: true) {
            VStack(alignment: .leading, spacing: Spacing.small) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.linear)
                    Text(title)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }

                AnimatedCounter(value)

                if let detail {
                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(.tertiary)
                }

                // Reserve the trend slot whether or not there is a series, so tiles in the
                // same grid row line up instead of ragging (CLAUDE.md §5.1).
                Group {
                    if trend.count > 1 {
                        Sparkline(values: trend, palette: palette)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 34)
                .padding(.top, Spacing.xxs)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        // One accessibility element per tile; reading icon, label and value separately is noise.
        .accessibilityElement(children: .combine)
    }
}

#Preview("MetricTile") {
    LazyVGrid(columns: [.init(.adaptive(minimum: 200), spacing: Spacing.large)], spacing: Spacing.large) {
        MetricTile(
            symbol: "internaldrive",
            title: "Disk",
            value: "412 GB",
            detail: "of 1 TB",
            palette: AppSection.files.palette,
            trend: (0..<40).map { _ in .random(in: 30...70) }
        )
        MetricTile(
            symbol: "memorychip",
            title: "Memory",
            value: "11.2 GB",
            palette: AppSection.performance.palette,
            trend: (0..<40).map { _ in .random(in: 40...90) }
        )
        MetricTile(
            symbol: "cpu",
            title: "CPU",
            value: "23%",
            palette: AppSection.dashboard.palette
        )
    }
    .padding(Spacing.xl)
    .frame(width: 700)
}
