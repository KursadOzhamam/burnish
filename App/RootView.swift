import SwiftUI
import CoreKit
import DesignSystem
import Dashboard
import SmartScan

/// Main window — sidebar plus detail, per CLAUDE.md §5.1.
struct RootView: View {
    @State private var selection: AppSection = .dashboard
    @State private var scanCoordinator = ScanCoordinator()

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: 640, ideal: 820)
        }
        .navigationSplitViewStyle(.balanced)
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
                phase: $scanCoordinator.phase,
                onStart: scanCoordinator.start,
                onCancel: scanCoordinator.cancel
            )

        default:
            PlaceholderView(section: selection)
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
