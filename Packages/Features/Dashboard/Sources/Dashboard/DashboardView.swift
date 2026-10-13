import SwiftUI
import CoreKit
import DesignSystem
import SystemMonitor

/// The Overview screen — CLAUDE.md §6.1, in the supplied design.
public struct DashboardView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var model: DashboardModel
    private let onStartScan: () -> Void
    private let onOpenSection: (AppSection) -> Void

    public init(
        model: DashboardModel = DashboardModel(),
        onStartScan: @escaping () -> Void = {},
        onOpenSection: @escaping (AppSection) -> Void = { _ in }
    ) {
        self._model = State(initialValue: model)
        self.onStartScan = onStartScan
        self.onOpenSection = onOpenSection
    }

    /// What the page is titled: this Mac's own name, as in the design ("My MacBook").
    private var computerName: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: Host.current().localizedName ?? model.snapshot.machine.model)
    }

    public var body: some View {
        SectionPage(
            title: computerName,
            subtitle: DashboardStrings.subtitle,
            actionTitle: DashboardStrings.scanAction,
            action: onStartScan
        ) {
            hero
        } content: {
            if !model.recommendations.isEmpty { recommendationsList }
            metricRow
        }
        // §8: polling runs only while this view is on screen.
        .task { model.startMonitoring() }
        .onDisappear(perform: model.stopMonitoring)
        .sheet(isPresented: $model.isShowingScoreBreakdown) {
            HealthScoreBreakdownView(score: model.score)
        }
    }

    // MARK: Hero

    /// The ring shows "not scanned" until a scan has measured something: a score before any
    /// measurement would be a number made up for decoration (CLAUDE.md §10.4).
    private var hasMeasured: Bool { model.lastScanDate != nil }

    private var hero: some View {
        let t = scheme.theme
        return HStack(spacing: 28) {
            VStack(spacing: 6) {
                if hasMeasured {
                    StatusRing(progress: Double(model.score.value) / 100, title: String(localized: DashboardStrings.healthTitle), value: "\(model.score.value)")
                    Button { model.isShowingScoreBreakdown = true } label: {
                        Text(DashboardStrings.healthExplain).font(.system(size: 11)).foregroundStyle(t.accent)
                    }
                    .buttonStyle(.plain)
                } else {
                    StatusRing(title: String(localized: DashboardStrings.neverScanned))
                }
            }
            Rectangle().fill(t.heroBorder).frame(width: 1, height: 130)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.snapshot.machine.model).font(.system(size: 19, weight: .semibold)).foregroundStyle(t.ink)
                Text(model.snapshot.machine.osVersion).font(.system(size: 12)).foregroundStyle(t.inkSecondary)
                Label {
                    if let lastScan = model.lastScanDate {
                        Text(lastScan, format: .relative(presentation: .named))
                    } else {
                        Text(DashboardStrings.neverScanned)
                    }
                } icon: { Image(systemName: "clock").font(.system(size: 11)) }
                .font(.system(size: 12)).foregroundStyle(t.inkTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            LaptopIllustration()
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .heroSurface()
    }

    // MARK: Suggestions

    private var recommendationsList: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(DashboardStrings.recTitle).font(.system(size: 12)).foregroundStyle(scheme.theme.inkSecondary)
            ForEach(model.recommendations) { recommendation in
                HStack {
                    Text(DashboardStrings.text(for: recommendation.kind)).font(.system(size: 13)).foregroundStyle(scheme.theme.ink)
                    Spacer()
                    Button { onOpenSection(recommendation.section) } label: { Text(DashboardStrings.recOpen) }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(scheme.theme.accent)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .cardSurface(radius: 12)
            }
        }
    }

    // MARK: Metrics

    private var metricRow: some View {
        let t = scheme.theme
        let snapshot = model.snapshot
        return HStack(alignment: .top, spacing: 16) {
            MetricCard(
                symbol: "internaldrive", title: DashboardStrings.diskFree, value: snapshot.disk.free.formatted(),
                detail: DashboardStrings.diskDetail(total: snapshot.disk.total.formatted())
            ) { BrandBar(fraction: snapshot.disk.freeFraction).padding(.top, 6) }

            MetricCard(symbol: "memorychip", title: DashboardStrings.memory, value: snapshot.memory.used.formatted()) {
                Sparkline(values: snapshot.memory.history, palette: AppSection.dashboard.palette).frame(height: 56)
            }

            MetricCard(
                symbol: "cpu", title: DashboardStrings.cpu,
                value: snapshot.cpu.total.formatted(.percent.precision(.fractionLength(0)))
            ) { Sparkline(values: snapshot.cpu.history, palette: AppSection.dashboard.palette).frame(height: 56) }

            MetricCard(
                symbol: "battery.75",
                title: DashboardStrings.battery,
                value: snapshot.battery.map { $0.charge.formatted(.percent.precision(.fractionLength(0))) } ?? "—"
            ) { if let battery = snapshot.battery { BrandBar(fraction: battery.charge).padding(.top, 6) } }

            MetricCard(
                symbol: "wifi", title: DashboardStrings.network, value: snapshot.network.download.formatted(),
                detail: DashboardStrings.networkDetail
            ) { Image(systemName: "arrow.down.to.line").font(.system(size: 14)).foregroundStyle(t.inkTertiary).padding(.top, 4) }
        }
    }
}

/// The "how was this calculated?" panel required by CLAUDE.md §6.1.
struct HealthScoreBreakdownView: View {
    let score: HealthScore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            SectionHeader(
                title: DashboardStrings.healthTitle,
                palette: AppSection.dashboard.palette
            )

            ForEach(score.components) { component in
                HStack {
                    Text(DashboardStrings.name(for: component.factor))
                        .font(Typography.body)
                    Spacer()
                    Text(component.measurement)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                    Text(
                        DashboardStrings.points(
                            earned: component.earned,
                            available: component.available
                        )
                    )
                    .numericStyle(Typography.caption)
                    .frame(width: 92, alignment: .trailing)
                }
            }

            Divider()

            HStack {
                Spacer()
                AnimatedCounter("\(score.value) / 100", font: Typography.cardTitle)
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.top, Spacing.xs)
        }
        .padding(Spacing.large)
        .frame(width: 460)
    }
}

#Preview("Dashboard") {
    DashboardView(
        model: DashboardModel(
            monitor: MockSystemMonitor(),
            lastScanDate: .now.addingTimeInterval(-7_200)
        )
    )
        .frame(width: 900, height: 700)
}

#Preview("Score breakdown") {
    HealthScoreBreakdownView(
        score: HealthScore.evaluate(
            snapshot: .sample,
            inputs: .init(threatCount: 0, pendingUpdateCount: 2, startupItemCount: 14)
        )
    )
}
