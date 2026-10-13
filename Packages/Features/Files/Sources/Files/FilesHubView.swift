import SwiftUI
import AppKit
import CoreKit
import CoreKitMac
import DesignSystem
import SafetyKit

/// The models behind the Files section. Owned by the window, so a scan survives switching to
/// another section and back.
@MainActor
public final class FilesModels {
    public let scope: ScanScope
    public let largeFiles: LargeFilesModel
    public let spaceLens: SpaceLensModel
    public let duplicates: DuplicatesModel
    public let similar: DuplicatesModel
    public let shredder: ShredderModel

    public init(history: HistoryStore?, defaults: UserDefaults? = .standard) {
        let scope = ScanScope(defaults: defaults)
        self.scope = scope
        largeFiles = LargeFilesModel(scope: scope, history: history)
        spaceLens = SpaceLensModel(scope: scope, history: history)
        duplicates = DuplicatesModel(scope: scope, history: history)
        similar = DuplicatesModel(kind: .similar, scope: scope, history: history)
        shredder = ShredderModel(history: history)
    }
}

/// The Files section: one place for the large-files list and the space map.
public struct FilesHubView: View {
    private enum Tab: Hashable { case landing, large, map, duplicates, similar, shredder }

    @State private var tab: Tab = .landing
    @Environment(\.colorScheme) private var colorScheme
    @State private var isEditingScope = false
    /// Nil when it cannot be determined; the notice shows only when access is known to be missing.
    @State private var hasFullDiskAccess: Bool?
    private let models: FilesModels

    public init(models: FilesModels) {
        self.models = models
    }

    public var body: some View {
        Group {
            if tab == .landing { landing } else { tool }
        }
        .sheet(isPresented: $isEditingScope) { ScopeView(scope: models.scope) { isEditingScope = false } }
        // Probed once the page is up, not while it is being constructed.
        .task { hasFullDiskAccess = FullDiskAccess.isGranted() }
        // Re-check when the user comes back from System Settings, so the notice disappears by itself.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFullDiskAccess = FullDiskAccess.isGranted()
        }
    }

    // MARK: Landing (the supplied design)

    /// Free and total space of the volume holding the home folder.
    private var diskSpace: (free: Int64, total: Int64)? {
        let values = try? FileManager.default.homeDirectoryForCurrentUser.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        )
        guard let free = values?.volumeAvailableCapacityForImportantUsage, let total = values?.volumeTotalCapacity else { return nil }
        return (free, Int64(total))
    }

    private var landing: some View {
        let rows = [
            FeatureRow(symbol: "doc.on.doc", title: FilesStrings.landingRowLarge, detail: FilesStrings.landingRowLargeDetail,
                       status: FilesStrings.landingStatusOpen) { tab = .large },
            FeatureRow(symbol: "square.on.square", title: FilesStrings.landingRowDuplicates, detail: FilesStrings.landingRowDuplicatesDetail,
                       status: FilesStrings.landingStatusOpen) { tab = .duplicates },
            FeatureRow(symbol: "photo.on.rectangle", title: FilesStrings.landingRowSimilar, detail: FilesStrings.landingRowSimilarDetail,
                       status: FilesStrings.landingStatusOpen) { tab = .similar },
            FeatureRow(symbol: "calendar.badge.clock", title: FilesStrings.landingRowOld, detail: FilesStrings.landingRowOldDetail,
                       status: FilesStrings.landingStatusOpen) {
                models.largeFiles.ageFilter = .overOneYear
                tab = .large
            },
            FeatureRow(symbol: "chart.pie", title: FilesStrings.landingRowMap, detail: FilesStrings.landingRowMapDetail,
                       status: FilesStrings.landingStatusOpen) { tab = .map },
            FeatureRow(symbol: "scissors", title: FilesStrings.landingRowShredder, detail: FilesStrings.landingRowShredderDetail,
                       status: FilesStrings.landingStatusOpen) { tab = .shredder }
        ]
        let space = diskSpace
        return SectionPage(
            title: FilesStrings.landingTitle,
            subtitle: FilesStrings.landingSubtitle,
            footer: PageFooter(
                lastScan: String(localized: FilesStrings.landingLastScan), note: FilesStrings.landingFooter,
                machine: MachineLabel.model, system: MachineLabel.system
            ),
            actionTitle: FilesStrings.landingAction,
            action: {
                tab = .large
                models.largeFiles.scan()
            }
        ) {
            HeroCard(heading: FilesStrings.landingHeroHeading, message: FilesStrings.landingHeroMessage, note: FilesStrings.landingHeroNote) {
                StatusRing(symbol: "chart.pie", title: String(localized: FilesStrings.landingNotScanned))
            } trailing: {
                IllustrationTile(symbol: "chart.pie", badge: "folder.badge.magnifyingglass")
            }
        } content: {
            HStack(alignment: .top, spacing: 16) {
                FeatureListCard(heading: FilesStrings.landingList, trailingHeading: FilesStrings.landingListWaiting, rows: rows)
                    .frame(maxWidth: .infinity)
                InfoCard(
                    symbol: "internaldrive", heading: FilesStrings.landingFreeHeading, message: FilesStrings.landingFreeMessage,
                    buttonTitle: FilesStrings.landingFreeButton, buttonSymbol: "folder", action: { isEditingScope = true }
                ) {
                    if let space {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(ByteCount(space.free).formatted()).font(.system(size: 26, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(colorScheme.theme.ink)
                            BrandBar(fraction: Double(space.free) / Double(max(1, space.total)))
                        }
                    }
                }
                .frame(width: 280)
            }
        }
    }

    private var tool: some View {
        VStack(spacing: 0) {
            Button { tab = .landing } label: {
                Label { Text(FilesStrings.back) } icon: { Image(systemName: "chevron.left") }
            }
            .buttonStyle(.plain)
            .foregroundStyle(colorScheme.theme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Spacing.large)
            .padding(.top, Spacing.large + 24)
            if hasFullDiskAccess == false { accessNotice }
            HStack(spacing: Spacing.medium) {
                Picker(selection: $tab) {
                    Text(FilesStrings.hubLarge).tag(Tab.large)
                    Text(FilesStrings.hubMap).tag(Tab.map)
                    Text(FilesStrings.hubDuplicates).tag(Tab.duplicates)
                    Text(FilesStrings.hubSimilar).tag(Tab.similar)
                    Text(FilesStrings.hubShredder).tag(Tab.shredder)
                } label: { EmptyView() }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 640)

                if tab != .shredder {
                    Button { isEditingScope = true } label: {
                        Label { Text(FilesStrings.scopeButton) } icon: { Image(systemName: "folder.badge.gearshape") }
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.top, Spacing.medium)

            switch tab {
            case .landing: EmptyView()
            case .large: LargeFilesView(model: models.largeFiles)
            case .map: SpaceLensView(model: models.spaceLens)
            case .duplicates: DuplicatesView(model: models.duplicates)
            case .similar: DuplicatesView(model: models.similar)
            case .shredder: ShredderView(model: models.shredder)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme.theme.background.ignoresSafeArea())
    }

    private var accessNotice: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Image(systemName: "lock.shield").foregroundStyle(.secondary)
            Text(FilesStrings.fdaNotice)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                if let url = URL(string: FullDiskAccess.settingsURLString) { NSWorkspace.shared.open(url) }
            } label: { Text(FilesStrings.fdaOpen) }
        }
        .padding(Spacing.small)
        .background { RoundedRectangle(cornerRadius: CornerRadius.medium).fill(.quaternary) }
        .padding(.horizontal, Spacing.large)
        .padding(.top, Spacing.medium)
    }
}
