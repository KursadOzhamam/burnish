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
    @State private var selection: AppSection = .dashboard
    @State private var scanCoordinator = ScanCoordinator(history: Self.history)

    /// Same log as Cleanup writes to, so what was just removed is what the sheet lists.
    @State private var historyModel = HistoryModel(store: Self.history)
    @State private var showHistory = false
    @State private var filesModels = FilesModels(history: Self.history)
    @State private var applicationsModel = ApplicationsModel(history: Self.history)
    @State private var performanceModel = PerformanceModel()
    @AppStorage("onboarding.done") private var onboardingDone = false
    @AppStorage("schedule.frequency") private var scheduleFrequency = "off"
    @State private var scheduler: ScanScheduler?
    @State private var dashboardModel = DashboardModel()
    @State private var privacyModel = CleanupModel.privacy(history: Self.history)
    @State private var protectionModel = ProtectionModel(supportDirectory: Self.supportDirectory)

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: 640, ideal: 820)
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

    private var sidebar: some View {
        List(AppSection.allCases, selection: $selection) { section in
            NavigationLink(value: section) {
                Label {
                    Text(section.title)
                } icon: {
                    Image(systemName: section.symbol)
                        .foregroundStyle(section.palette.linear)
                }
            }
            .tag(section)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 280)
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
