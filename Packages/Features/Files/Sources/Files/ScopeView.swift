import SwiftUI
import AppKit
import DesignSystem

/// Where the Files screens look, and what they skip (CLAUDE.md §6.9).
struct ScopeView: View {
    let scope: ScanScope
    let onDone: () -> Void

    @State private var isAddingFolder = false
    @State private var isExcludingFolder = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            SectionHeader(title: FilesStrings.scopeTitle, subtitle: FilesStrings.scopeSubtitle, palette: AppSection.files.palette)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(scope.candidates, id: \.path) { url in
                        HStack {
                            Toggle(isOn: Binding(get: { scope.isEnabled(url) }, set: { scope.setEnabled($0, for: url) })) {
                                Text(Self.display(url)).font(Typography.body).lineLimit(1).truncationMode(.middle)
                            }
                            .toggleStyle(.checkbox)
                            Spacer()
                            if !scope.isDefault(url) {
                                Button { scope.remove(url) } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(Text(FilesStrings.scopeRemove))
                            }
                        }
                    }

                    Text(FilesStrings.scopeExcluded).font(Typography.caption).foregroundStyle(.secondary).padding(.top, Spacing.small)
                    if scope.excluded.isEmpty {
                        Text(FilesStrings.scopeNoneExcluded).font(Typography.caption).foregroundStyle(.tertiary)
                    }
                    ForEach(scope.excluded, id: \.path) { url in
                        HStack {
                            Image(systemName: "nosign").foregroundStyle(.secondary)
                            Text(Self.display(url)).font(Typography.body).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { scope.include(url) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(Text(FilesStrings.scopeRemove))
                        }
                    }
                }
            }
            .frame(maxHeight: 280)

            HStack {
                Button { isAddingFolder = true } label: { Text(FilesStrings.scopeAddFolder) }
                Menu {
                    let volumes = ScanScope.mountedVolumes()
                    if volumes.isEmpty {
                        Text(FilesStrings.scopeNoVolumes)
                    }
                    ForEach(volumes, id: \.path) { volume in
                        Button(volume.lastPathComponent) { scope.add(volume) }
                    }
                } label: { Text(FilesStrings.scopeAddVolume) }
                .fixedSize()
                Button { isExcludingFolder = true } label: { Text(FilesStrings.scopeExclude) }
                Spacer()
                Button(action: onDone) { Text(FilesStrings.scopeDone).frame(minWidth: 80) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.large)
        .frame(width: 560)
        .fileImporter(isPresented: $isAddingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { urls.forEach(scope.add) }
        }
        .fileImporter(isPresented: $isExcludingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { urls.forEach(scope.exclude) }
        }
    }

    private static func display(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}
