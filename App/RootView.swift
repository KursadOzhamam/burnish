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
        .sheet(isPresented: $showHistory) {
            HistoryView(model: historyModel)
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
                model: DashboardModel(),
                onStartScan: {
                    selection = .smartScan
                    scanCoordinator.start()
                }
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
