import SwiftUI
import UniformTypeIdentifiers
import CoreKit
import DesignSystem
import DeletionUI
import ScanEngine
import SafetyKit

/// The shredder screen — CLAUDE.md §6.7.
public struct ShredderView: View {
    @State private var model: ShredderModel
    @State private var isPickingFiles = false
    @State private var isTargeted = false

    private var section: AppSection { .files }

    public init(model: ShredderModel = ShredderModel()) {
        self._model = State(initialValue: model)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            SectionHeader(title: FilesStrings.shredTitle, subtitle: FilesStrings.shredSubtitle, palette: section.palette)

            switch model.phase {
            case .idle: content
            case .deleting: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .finished(let report):
                DeletionResultView(report: report, section: section) { model.reset() }
            }
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pageBackground()
        .fileImporter(isPresented: $isPickingFiles, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await model.add(urls) } }
        }
        .sheet(item: Binding(
            get: { model.pendingPlan.map(IdentifiedPlan.init) },
            set: { if $0 == nil { model.dismissConfirmation() } }
        )) { wrapper in
            ConfirmationSheet(
                plan: wrapper.plan,
                section: section,
                canRecordHistory: model.canRecordHistory,
                onCancel: model.dismissConfirmation,
                onConfirm: { model.confirm(wrapper.plan) }
            )
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            dropZone
            if !model.entries.isEmpty {
                ScrollView {
                    LazyVStack(spacing: Spacing.xxs) {
                        ForEach(model.entries) { item in row(item) }
                    }
                }
            } else {
                Spacer(minLength: 0)
            }
            footer
        }
        .frame(maxHeight: .infinity)
    }

    private var dropZone: some View {
        VStack(spacing: Spacing.small) {
            Image(systemName: "tray.and.arrow.down").font(.title2).foregroundStyle(.secondary)
            Text(FilesStrings.shredDrop).font(Typography.caption).foregroundStyle(.secondary)
            Button { isPickingFiles = true } label: { Text(FilesStrings.shredAdd) }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.large)
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(isTargeted ? AnyShapeStyle(section.palette.linear) : AnyShapeStyle(.quaternary))
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await model.add(urls) }
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private func row(_ item: ScanItem) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: item.isActionable ? "doc" : "lock.fill")
                .foregroundStyle(item.isActionable ? AnyShapeStyle(.secondary) : AnyShapeStyle(Semantic.warning.color))
            Text(item.displayName).font(Typography.body).lineLimit(1)
            Text((item.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                .font(Typography.path).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
            Spacer(minLength: Spacing.small)
            if !item.isActionable {
                Text(FilesStrings.shredBlocked).font(Typography.caption).foregroundStyle(.secondary)
            } else {
                Text(item.size.formatted()).numericStyle(Typography.caption).foregroundStyle(.secondary)
            }
            Button { model.remove(item) } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(FilesStrings.shredRemove))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(FilesStrings.shredHonest)
                .font(Typography.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Toggle(isOn: $model.acknowledgedIrreversible) { Text(FilesStrings.shredAcknowledge) }
                    .toggleStyle(.checkbox)
                    .disabled(model.actionable.isEmpty)
                Spacer()
                Button(action: model.clear) { Text(FilesStrings.shredClear) }
                    .disabled(model.entries.isEmpty)
                Button(role: .destructive, action: model.prepareConfirmation) {
                    Text(FilesStrings.shredDelete).frame(minWidth: 150)
                }
                .buttonStyle(.borderedProminent)
                .tint(Semantic.danger.color)
                .controlSize(.large)
                .disabled(!model.canPrepare)
            }
        }
    }
}

private struct IdentifiedPlan: Identifiable, Equatable {
    let plan: DeletionPlan
    var id: Int { plan.hashValue }
}
