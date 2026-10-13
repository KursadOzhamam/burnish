import SwiftUI
import DesignSystem
import SafetyKit

/// The models behind the Files section. Owned by the window, so a scan survives switching to
/// another section and back.
@MainActor
public final class FilesModels {
    public let largeFiles: LargeFilesModel
    public let spaceLens: SpaceLensModel
    public let duplicates: DuplicatesModel

    public init(history: HistoryStore?) {
        largeFiles = LargeFilesModel(history: history)
        spaceLens = SpaceLensModel(history: history)
        duplicates = DuplicatesModel(history: history)
    }
}

/// The Files section: one place for the large-files list and the space map.
public struct FilesHubView: View {
    private enum Tab: Hashable { case large, map, duplicates }

    @State private var tab: Tab = .large
    private let models: FilesModels

    public init(models: FilesModels) {
        self.models = models
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker(selection: $tab) {
                Text(FilesStrings.hubLarge).tag(Tab.large)
                Text(FilesStrings.hubMap).tag(Tab.map)
                Text(FilesStrings.hubDuplicates).tag(Tab.duplicates)
            } label: { EmptyView() }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 440)
            .padding(.top, Spacing.medium)

            switch tab {
            case .large: LargeFilesView(model: models.largeFiles)
            case .map: SpaceLensView(model: models.spaceLens)
            case .duplicates: DuplicatesView(model: models.duplicates)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
