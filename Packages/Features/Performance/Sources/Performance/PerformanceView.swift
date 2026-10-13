import SwiftUI
import AppKit
import CoreKit
import DesignSystem
import HelperProtocol
import CoreKitMac
import SystemMonitor

/// The Performance screen — CLAUDE.md §6.5.
public struct PerformanceView: View {
    private enum Tab: Hashable { case landing, maintenance, startup, processes }

    @State private var model: PerformanceModel
    @State private var tab: Tab = .landing
    @State private var snapshot: SystemSnapshot?
    @Environment(\.colorScheme) private var colorScheme

    private var section: AppSection { .performance }

    public init(model: PerformanceModel = PerformanceModel()) {
        self._model = State(initialValue: model)
    }

    public var body: some View {
        if tab == .landing { landing } else { tool }
    }

    private var tool: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            Button { tab = .landing } label: {
                Label { Text(PerfStrings.back) } icon: { Image(systemName: "chevron.left") }
            }
            .buttonStyle(.plain)
            .foregroundStyle(colorScheme.theme.accent)
            SectionHeader(title: PerfStrings.title, subtitle: PerfStrings.subtitle, palette: section.palette)

            Picker(selection: $tab) {
                Text(PerfStrings.tabMaintenance).tag(Tab.maintenance)
                Text(PerfStrings.tabStartup).tag(Tab.startup)
                Text(PerfStrings.tabProcesses).tag(Tab.processes)
            } label: { EmptyView() }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 520, alignment: .leading)

            switch tab {
            case .landing: EmptyView()
            case .maintenance: maintenance
            case .startup: startup
            case .processes: processes
            }
        }
        .padding(Spacing.large)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colorScheme.theme.background.ignoresSafeArea())
        .task { await model.refreshHelper() }
    }

    // MARK: Landing (the supplied design)

    private var landing: some View {
        let rows = [
            FeatureRow(symbol: "power", title: PerfStrings.landingRowStartup, detail: PerfStrings.landingRowStartupDetail,
                       status: PerfStrings.landingStatusReview) { tab = .startup },
            FeatureRow(symbol: "square.3.layers.3d", title: PerfStrings.landingRowBackground, detail: PerfStrings.landingRowBackgroundDetail,
                       status: PerfStrings.landingStatusReview) { tab = .startup },
            FeatureRow(symbol: "wrench.and.screwdriver", title: PerfStrings.landingRowMaintenance, detail: PerfStrings.landingRowMaintenanceDetail,
                       status: PerfStrings.landingStatusReview) { tab = .maintenance },
            FeatureRow(symbol: "memorychip", title: PerfStrings.landingRowMemory, detail: PerfStrings.landingRowMemoryDetail,
                       status: PerfStrings.landingStatusReview) { tab = .processes }
        ]
        return SectionPage(
            title: PerfStrings.title,
            subtitle: PerfStrings.landingSubtitle,
            footer: PageFooter(
                lastScan: String(localized: PerfStrings.landingLastScan), note: PerfStrings.landingFooter,
                machine: MachineLabel.model, system: MachineLabel.system
            ),
            actionTitle: PerfStrings.landingAction,
            action: { tab = .startup }
        ) {
            HeroCard(heading: PerfStrings.landingHeroHeading, message: PerfStrings.landingHeroMessage, note: PerfStrings.landingHeroNote) {
                StatusRing(symbol: "gauge.with.dots.needle.33percent", title: String(localized: PerfStrings.landingNotScanned))
            } trailing: {
                IllustrationTile(symbol: "gauge.with.dots.needle.33percent", badge: "bolt")
            }
        } content: {
            HStack(alignment: .top, spacing: 16) {
                MetricCard(
                    symbol: "memorychip", title: PerfStrings.landingMemory,
                    value: snapshot?.memory.used.formatted() ?? "—", detail: PerfStrings.landingMemoryNote
                ) { BrandBar(fraction: snapshot?.memory.usedFraction ?? 0).padding(.top, 6) }
                .frame(width: 190)
                MetricCard(
                    symbol: "cpu", title: PerfStrings.landingCpu,
                    value: snapshot.map { $0.cpu.total.formatted(.percent.precision(.fractionLength(0))) } ?? "—", detail: PerfStrings.landingCpuNote
                ) { BrandBar(fraction: snapshot?.cpu.total ?? 0).padding(.top, 6) }
                .frame(width: 190)
                FeatureListCard(heading: PerfStrings.landingList, trailingHeading: PerfStrings.landingListWaiting, rows: rows)
                    .frame(maxWidth: .infinity)
            }
        }
        // Readings only while this page is on screen (CLAUDE.md §8).
        .task {
            for await reading in LiveSystemMonitor().stream(interval: .seconds(2)) {
                if Task.isCancelled { break }
                snapshot = reading
            }
        }
    }

    // MARK: Maintenance

    private var maintenance: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                helperCard
                ForEach(MaintenanceTask.allCases) { task in taskRow(task) }
            }
        }
    }

    private var helperCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(PerfStrings.helperTitle).font(Typography.body.weight(.semibold))
            Text(helperText).font(Typography.caption).foregroundStyle(.secondary)
            HStack {
                if model.helperStatus == .notRegistered || model.helperStatus == .versionMismatch {
                    Button { Task { await model.installHelper() } } label: { Text(PerfStrings.helperInstall) }
                }
                if model.helperStatus == .requiresApproval {
                    Button(action: model.openLoginItemsSettings) { Text(PerfStrings.helperOpenSettings) }
                }
                if case .failed(let message) = model.helperStatus {
                    Text(message).font(Typography.caption).foregroundStyle(.tertiary).lineLimit(2)
                    Button { Task { await model.installHelper() } } label: { Text(PerfStrings.helperInstall) }
                }
            }
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: CornerRadius.medium).fill(.quaternary.opacity(0.5)) }
    }

    private var helperText: LocalizedStringResource {
        switch model.helperStatus {
        case .notRegistered: PerfStrings.helperNotRegistered
        case .requiresApproval: PerfStrings.helperRequiresApproval
        case .enabled: PerfStrings.helperEnabled
        case .notFound: PerfStrings.helperNotFound
        case .versionMismatch: PerfStrings.helperVersionMismatch
        case .failed: PerfStrings.helperFailed
        }
    }

    private func taskRow(_ task: MaintenanceTask) -> some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PerfStrings.task(task)).font(Typography.body)
                Text(PerfStrings.taskDetail(task)).font(Typography.caption).foregroundStyle(.secondary)
                switch model.state(of: task) {
                case .succeeded(let text) where !text.isEmpty:
                    Text(text).font(Typography.path).foregroundStyle(.tertiary).lineLimit(3)
                case .failed(let text):
                    Text(text).font(Typography.path).foregroundStyle(Semantic.warning.color).lineLimit(3)
                default: EmptyView()
                }
            }
            Spacer()
            if model.state(of: task) == .running {
                ProgressView().controlSize(.small)
            } else if model.canRun(task) {
                Button { Task { await model.run(task) } } label: { Text(PerfStrings.taskRun) }
            } else {
                Text(PerfStrings.taskNeedsHelper).font(Typography.caption).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Startup items

    private var startup: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text(PerfStrings.startupNote).font(Typography.caption).foregroundStyle(.secondary)
            if let error = model.launchError {
                Text(error).font(Typography.caption).foregroundStyle(Semantic.warning.color)
            }
            ScrollView {
                LazyVStack(spacing: Spacing.xs) {
                    ForEach(model.launchItems) { item in launchRow(item) }
                }
            }
        }
        .task { await model.loadLaunchItems() }
    }

    private func launchRow(_ item: LaunchItem) -> some View {
        HStack(spacing: Spacing.small) {
            VStack(alignment: .leading, spacing: 0) {
                Text(item.label).font(Typography.body).lineLimit(1).truncationMode(.middle)
                HStack(spacing: Spacing.xs) {
                    Text(scopeText(item)).font(Typography.caption).foregroundStyle(.tertiary)
                    if item.isProgramMissing {
                        Text(PerfStrings.startupMissing).font(Typography.caption).foregroundStyle(Semantic.warning.color)
                    }
                }
            }
            Spacer()
            Toggle(isOn: Binding(
                get: { model.isEnabled(item) },
                set: { isOn in Task { await model.setEnabled(item, to: isOn) } }
            )) { Text(item.label) }
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(!item.canBeDisabledByUser)
        }
    }

    private func scopeText(_ item: LaunchItem) -> LocalizedStringResource {
        if item.isApple { return PerfStrings.startupApple }
        switch item.scope {
        case .userAgent: return PerfStrings.startupUserAgent
        case .globalAgent: return PerfStrings.startupGlobalAgent
        case .daemon: return PerfStrings.startupDaemon
        }
    }

    // MARK: Processes

    private var processes: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text(PerfStrings.processesNote).font(Typography.caption).foregroundStyle(.secondary)
            Toggle(isOn: Binding(get: { model.notifiesOnMemoryPressure }, set: { model.setNotifiesOnMemoryPressure($0) })) {
                Text(PerfStrings.pressureToggle)
            }
            .toggleStyle(.checkbox)
            HStack(alignment: .top, spacing: Spacing.large) {
                processColumn(title: PerfStrings.processesCpu) {
                    ForEach(model.topCPU) { load in
                        processRow(load.sample, trailing: "\(Int(load.cpuPercent.rounded()))%")
                    }
                }
                processColumn(title: PerfStrings.processesMemory) {
                    ForEach(model.topMemory) { sample in
                        processRow(sample, trailing: ByteCount(Int64(sample.residentBytes)).formatted())
                    }
                }
            }
        }
        // Sampling runs only while this tab is on screen (CLAUDE.md §8).
        .task {
            while !Task.isCancelled {
                await model.refreshProcesses()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func processColumn<Content: View>(title: LocalizedStringResource, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).font(Typography.caption).foregroundStyle(.secondary)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func processRow(_ sample: ProcessSample, trailing: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(sample.name).font(Typography.body).lineLimit(1)
            Spacer(minLength: Spacing.xs)
            Text(trailing).numericStyle(Typography.caption).foregroundStyle(.secondary)
            if model.canQuit(sample) {
                Button { model.requestQuit(sample) } label: { Text(PerfStrings.processesQuit) }
                    .buttonStyle(.borderless)
                    .font(Typography.caption)
            }
        }
    }
}
