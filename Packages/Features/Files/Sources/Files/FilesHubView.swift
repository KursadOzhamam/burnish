import SwiftUI
import AppKit
import CoreKitMac
import DesignSystem
import SafetyKit

/// The models behind the Files section. Owned by the window, so a scan survives switching to
/// another section and back.
@MainActor
public final class FilesModels {
    public let largeFiles: LargeFilesModel
    public let spaceLens: SpaceLensModel
    public let duplicates: DuplicatesModel
    public let similar: DuplicatesModel
    public let shredder: ShredderModel

    public init(history: HistoryStore?) {
        largeFiles = LargeFilesModel(history: history)
        spaceLens = SpaceLensModel(history: history)
        duplicates = DuplicatesModel(history: history)
        similar = DuplicatesModel(kind: .similar, history: history)
        shredder = ShredderModel(history: history)
    }
}

/// The Files section: one place for the large-files list and the space map.
public struct FilesHubView: View {
    private enum Tab: Hashable { case large, map, duplicates, similar, shredder }

    @State private var tab: Tab = .large
    /// Nil when it cannot be determined; the notice shows only when access is known to be missing.
    @State private var hasFullDiskAccess: Bool? = FullDiskAccess.isGranted()
    private let models: FilesModels

    public init(models: FilesModels) {
        self.models = models
    }

    public var body: some View {
        VStack(spacing: 0) {
            if hasFullDiskAccess == false { accessNotice }
            Picker(selection: $tab) {
                Text(FilesStrings.hubLarge).tag(Tab.large)
                Text(FilesStrings.hubMap).tag(Tab.map)
                Text(FilesStrings.hubDuplicates).tag(Tab.duplicates)
                Text(FilesStrings.hubSimilar).tag(Tab.similar)
                Text(FilesStrings.hubShredder).tag(Tab.shredder)
            } label: { EmptyView() }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 720)
            .padding(.top, Spacing.medium)

            switch tab {
            case .large: LargeFilesView(model: models.largeFiles)
            case .map: SpaceLensView(model: models.spaceLens)
            case .duplicates: DuplicatesView(model: models.duplicates)
            case .similar: DuplicatesView(model: models.similar)
            case .shredder: ShredderView(model: models.shredder)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        // Re-check when the user comes back from System Settings, so the notice disappears by itself.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFullDiskAccess = FullDiskAccess.isGranted()
        }
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
