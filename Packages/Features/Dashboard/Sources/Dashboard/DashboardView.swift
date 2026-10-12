import SwiftUI
import CoreKit
import DesignSystem
import SystemMonitor

/// The Overview screen — CLAUDE.md §6.1.
public struct DashboardView: View {
    @State private var model: DashboardModel
    private let onStartScan: () -> Void

    private var section: AppSection { .dashboard }

    public init(model: DashboardModel = DashboardModel(), onStartScan: @escaping () -> Void = {}) {
        self._model = State(initialValue: model)
        self.onStartScan = onStartScan
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                SectionHeader(
                    title: DashboardStrings.title,
                    subtitle: DashboardStrings.subtitle,
                    palette: section.palette
                )

                heroCard

                metricGrid
            }
            .padding(Spacing.large)
        }
        .background(.background)
        // §8: polling runs only while this view is on screen.
        .task {
            model.startMonitoring()
        }
        .onDisappear(perform: model.stopMonitoring)
        .sheet(isPresented: $model.isShowingScoreBreakdown) {
            HealthScoreBreakdownView(score: model.score)
        }
    }

    private var heroCard: some View {
        GlassCard(cornerRadius: CornerRadius.xl, padding: Spacing.large) {
            HStack(alignment: .center, spacing: Spacing.xl) {
                scoreRing

                VStack(alignment: .leading, spacing: Spacing.small) {
                    Text(model.snapshot.machine.model)
                        .font(Typography.cardTitle)
                    Text(model.snapshot.machine.osVersion)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)

                    if let lastScan = model.lastScanDate {
                        Text(lastScan, format: .relative(presentation: .named))
                            .font(Typography.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(DashboardStrings.neverScanned)
                            .font(Typography.caption)
                            .foregroundStyle(.tertiary)
                    }

                    ScanButton(
                        title: DashboardStrings.scanAction,
                        palette: AppSection.smartScan.textSafePalette,
                        action: onStartScan
                    )
                    .padding(.top, Spacing.xs)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var scoreRing: some View {
        VStack(spacing: Spacing.xs) {
            ZStack {
                GradientRing(
                    progress: Double(model.score.value) / 100,
                    palette: section.palette,
                    lineWidth: 16
                )
                AnimatedCounter("\(model.score.value)", font: Typography.hero)
                    .frame(maxWidth: 108)
            }
            .frame(width: 164, height: 164)

            Button {
                model.isShowingScoreBreakdown = true
            } label: {
                Text(DashboardStrings.healthExplain)
                    .font(Typography.caption)
            }
            .buttonStyle(.link)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(DashboardStrings.healthTitle))
        .accessibilityValue("\(model.score.value)")
    }

    private var metricGrid: some View {
        LazyVGrid(
            columns: [.init(.adaptive(minimum: 210), spacing: Spacing.large)],
            spacing: Spacing.large
        ) {
            MetricTile(
                symbol: "internaldrive",
                title: DashboardStrings.diskFree,
                value: model.snapshot.disk.free.formatted(),
                detail: DashboardStrings.diskDetail(total: model.snapshot.disk.total.formatted()),
                palette: AppSection.files.palette
            )

            MetricTile(
                symbol: "memorychip",
                title: DashboardStrings.memory,
                value: model.snapshot.memory.used.formatted(),
                palette: AppSection.performance.palette,
                trend: model.snapshot.memory.history
            )

            MetricTile(
                symbol: "cpu",
                title: DashboardStrings.cpu,
                value: model.snapshot.cpu.total.formatted(.percent.precision(.fractionLength(0))),
                palette: section.palette,
                trend: model.snapshot.cpu.history
            )

            if let battery = model.snapshot.battery {
                MetricTile(
                    symbol: battery.isCharging ? "battery.100.bolt" : "battery.75",
                    title: DashboardStrings.battery,
                    value: battery.charge.formatted(.percent.precision(.fractionLength(0))),
                    palette: AppSection.cleanup.palette
                )
            }

            MetricTile(
                symbol: "arrow.down.arrow.up",
                title: DashboardStrings.network,
                value: model.snapshot.network.download.formatted(),
                detail: DashboardStrings.networkDetail,
                palette: AppSection.applications.palette
            )
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
    DashboardView(model: DashboardModel(lastScanDate: .now.addingTimeInterval(-7_200)))
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
