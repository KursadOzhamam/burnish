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
    private let animatesValue: Bool

    /// - Parameter animatesValue: whether the figure morphs between values.
    ///
    ///   Off by default, and deliberately so. A live metric refreshes once a second (§8), and a
    ///   spring-animated numeric transition at that rate costs roughly half the dashboard's
    ///   entire CPU budget — measured, not guessed — while making the number harder to read
    ///   because it is almost never at rest. `AnimatedCounter` earns its keep on figures that
    ///   change at moments that matter: the scan total and the health score. For a CPU
    ///   percentage ticking every second it is the wrong tool.
    public init(
        symbol: String,
        title: LocalizedStringResource,
        value: String,
        detail: LocalizedStringResource? = nil,
        palette: GradientPair,
        trend: [Double] = [],
        animatesValue: Bool = false
    ) {
        self.symbol = symbol
        self.title = title
        self.value = value
        self.detail = detail
        self.palette = palette
        self.trend = trend
        self.animatesValue = animatesValue
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

                if animatesValue {
                    AnimatedCounter(value)
                } else {
                    // Monospaced digits keep the figure from jittering as it changes.
                    Text(value).numericStyle(Typography.metric)
                }

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
