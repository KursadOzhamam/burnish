import SwiftUI
import CoreKit
import SafetyKit
import DesignSystem
import Applications
import Cleanup
import Dashboard
import Files
import History
import Performance
import Protection
import SmartScan

/// Main window — sidebar plus detail, per CLAUDE.md §5.1.
struct RootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: AppSection = .dashboard

    /// Same log as Cleanup writes to, so what was just removed is what the sheet lists.
    @State private var showHistory = false
    @AppStorage("onboarding.done") private var onboardingDone = false
    @AppStorage("schedule.frequency") private var scheduleFrequency = "off"
    @State private var scheduler: ScanScheduler?
    /// Created once for the whole run. As `@State` initial values these were rebuilt every time the
    /// view struct was re-created, which repeated file and process work on every refresh.
    private let models = AppModels.shared
    private var scanCoordinator: ScanCoordinator { models.scanCoordinator }
    private var historyModel: HistoryModel { models.historyModel }
    private var filesModels: FilesModels { models.filesModels }
    private var applicationsModel: ApplicationsModel { models.applicationsModel }
    private var performanceModel: PerformanceModel { models.performanceModel }
    private var dashboardModel: DashboardModel { models.dashboardModel }
    private var privacyModel: CleanupModel { models.privacyModel }
    private var protectionModel: ProtectionModel { models.protectionModel }

    var body: some View {
        // The window is the container. The page's round action is drawn across its bottom edge by
        // a child window (see `FloatingActionHost`), so nothing is reserved around the window.
        container
            .backgroundPreferenceValue(FloatingActionKey.self) { action in
                FloatingActionHost(action: action)
            }
    }

    private var container: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: 640, ideal: 820)
                .environment(\.hostsFloatingAction, true)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showHistory = true
                } label: {
                    Label("toolbar.history", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .sheet(isPresented: Binding(get: { !onboardingDone }, set: { if !$0 { onboardingDone = true } })) {
            OnboardingView { onboardingDone = true }
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(model: historyModel)
        }
        .onReceive(NotificationCenter.default.publisher(for: .burnishStartSmartScan)) { _ in
            selection = .smartScan
            scanCoordinator.start()
        }
        .task {
            await performanceModel.loadLaunchItems()
            scheduler = ScanScheduler(coordinator: scanCoordinator)
            scheduler?.apply(ScanSchedule.Frequency(rawValue: scheduleFrequency) ?? .off)
        }
        .onChange(of: scheduleFrequency) { _, value in
            scheduler?.apply(ScanSchedule.Frequency(rawValue: value) ?? .off)
        }
        // The health score is built only from what scans actually measured (CLAUDE.md §6.1, §10.4).
        .onChange(of: protectionModel.lastScan) { _, date in
            guard let date else { return }
            let threats = protectionModel.findings.filter { $0.severity == .threat }.count
            dashboardModel.update(threatCount: threats, scannedAt: date)
        }
        .onChange(of: performanceModel.launchItems.count) { _, _ in
            let active = performanceModel.launchItems.filter { !$0.isApple && performanceModel.isEnabled($0) }.count
            dashboardModel.update(startupItemCount: active)
        }
        .onChange(of: scanCoordinator.cleanup.phase.isBusy) { wasBusy, isBusy in
            if wasBusy, !isBusy, !scanCoordinator.cleanup.categories.isEmpty {
                let cleanable = scanCoordinator.cleanup.categories.map {
                    (name: String(localized: CleanupScanner(rule: $0.rule).title), size: $0.totalSize)
                }
                dashboardModel.update(scannedAt: Date(), cleanable: cleanable)
            }
        }
    }

    /// The sidebar of the supplied design: soft grey, a lavender pill and a dot on the selected row.
    /// Smart Scan has no row of its own there: it is the round button on the overview.
    private var sidebar: some View {
        let theme = colorScheme.theme
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(AppSection.allCases.filter { $0 != .smartScan }) { section in
                let isSelected = selection == section || (selection == .smartScan && section == .dashboard)
                Button { selection = section } label: {
                    HStack(spacing: 12) {
                        Image(systemName: section.symbol)
                            .font(.system(size: 15))
                            .foregroundStyle(isSelected ? theme.accent : theme.inkSecondary)
                            .frame(width: 22)
                        Text(section.title)
                            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                            .foregroundStyle(isSelected ? theme.accent : theme.ink)
                        Spacer()
                        if isSelected { Circle().fill(theme.accent).frame(width: 5, height: 5) }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background {
                        if isSelected { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.selection) }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.top, 8)
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(theme.sidebar.ignoresSafeArea())
        .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 240)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .dashboard:
            DashboardView(
                model: dashboardModel,
                onStartScan: {
                    selection = .smartScan
                    scanCoordinator.start()
                },
                onOpenSection: { selection = $0 }
            )

        case .smartScan:
            SmartScanView(
                phase: scanCoordinator.phase,
                onStart: scanCoordinator.start,
                onCancel: scanCoordinator.cancel,
                onReview: { selection = .cleanup }
            )

        case .cleanup:
            CleanupView(model: scanCoordinator.cleanup)

        case .privacy:
            CleanupView.privacy(model: privacyModel)

        case .protection:
            ProtectionView(model: protectionModel)

        case .performance:
            PerformanceView(model: performanceModel)

        case .applications:
            ApplicationsView(model: applicationsModel)

        case .files:
            FilesHubView(models: filesModels)

        default:
            PlaceholderView(section: selection)
        }
    }
}

extension RootView {
    /// `~/Library/Application Support/<App>/`, where quarantine and the allow-list live.
    static var supportDirectory: URL {
        (try? AppIdentity.current.supportDirectory())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Burnish")
    }

    /// One log for the whole window, opened once.
    static let history: HistoryStore? = makeHistory()

    /// The operation log at `~/Library/Application Support/<App>/history.sqlite` (§4.7).
    ///
    /// A log that cannot be opened must not stop the app from running; cleanup still works,
    /// it just cannot offer restore afterwards.
    static func makeHistory() -> HistoryStore? {
        do {
            let directory = try AppIdentity.current.supportDirectory()
            return try HistoryStore(url: directory.appendingPathComponent("history.sqlite"))
        } catch {
            Log.module("App").error("history unavailable: \(error.localizedDescription)")
            return nil
        }
    }
}

/// Stand-in for sections that arrive in later phases.
///
/// Says so plainly rather than showing a fake screen — a cleaner that implies capabilities it
/// does not have is exactly what CLAUDE.md §10 rules out.
struct PlaceholderView: View {
    let section: AppSection

    var body: some View {
        VStack(spacing: Spacing.large) {
            SectionHeader(title: section.title, palette: section.palette)
            EmptyState(
                symbol: section.symbol,
                title: "placeholder.title",
                message: "placeholder.message"
            )
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
    }
}

#Preview("Root") {
    RootView()
        .frame(width: 1_100, height: 760)
}
