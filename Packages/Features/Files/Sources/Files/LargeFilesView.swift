import SwiftUI
import CoreKit
import DesignSystem
import DeletionUI
import ScanEngine
import SafetyKit

/// The large-files screen — CLAUDE.md §6.7.
public struct LargeFilesView: View {
    @State private var model: LargeFilesModel

    private var section: AppSection { .files }

    public init(model: LargeFilesModel = LargeFilesModel()) {
        self._model = State(initialValue: model)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            SectionHeader(title: FilesStrings.title, subtitle: FilesStrings.subtitle, palette: section.palette)

            switch model.phase {
            case .idle: idleState
            case .scanning(let progress, let remaining): scanningState(progress, remaining: remaining)
            case .reviewing(let wasCancelled): reviewState(wasCancelled: wasCancelled)
            case .failed: failedState
            case .deleting: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .finished(let report):
                DeletionResultView(report: report, section: section) { model.reset() }
            }
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pageBackground()
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

    private var idleState: some View {
        ToolIdleState(symbol: "doc.zipper", message: FilesStrings.subtitle, actionTitle: FilesStrings.scan, action: model.scan)
    }

    private func scanningState(_ progress: ScanProgress, remaining: TimeInterval?) -> some View {
        VStack(spacing: Spacing.large) {
            Spacer()
            GradientRing(
                progress: progress.fraction ?? 0,
                palette: section.palette,
                lineWidth: 14,
                isIndeterminate: progress.fraction == nil
            )
            .frame(width: 180, height: 180)
            .overlay {
                AnimatedCounter(progress.discovered.formatted(), font: Typography.metric)
                    .frame(maxWidth: 130)
            }
            Text(FilesStrings.found(count: progress.itemCount))
                .font(Typography.caption)
                .foregroundStyle(.secondary)
            if let remaining {
                Text(FilesStrings.remaining(Self.format(remaining)))
                    .font(Typography.caption)
                    .foregroundStyle(.tertiary)
            }
            Text(progress.currentPath ?? "")
                .font(Typography.path)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520, minHeight: 20)
            Button(role: .cancel, action: model.cancel) {
                Text(FilesStrings.cancel).frame(minWidth: 110)
            }
            .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var failedState: some View {
        VStack {
            Spacer()
            EmptyState(symbol: "lock", title: FilesStrings.permission, message: FilesStrings.permission)
            Button(action: model.scan) { Text(FilesStrings.rescan) }
                .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func reviewState(wasCancelled: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            if wasCancelled {
                Label { Text(FilesStrings.partial) } icon: { Image(systemName: "pause.circle") }
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
            filters
            if model.visibleItems.isEmpty {
                VStack {
                    Spacer()
                    EmptyState(
                        symbol: "checkmark.circle",
                        title: FilesStrings.emptyTitle,
                        message: FilesStrings.emptyDetail
                    )
                    Spacer()
                }
            } else {
                list
            }
            footer
        }
        .frame(maxHeight: .infinity)
    }

    private var filters: some View {
        HStack(spacing: Spacing.medium) {
            Picker(selection: $model.kindFilter) {
                Text(FilesStrings.allKinds).tag(FileKind?.none)
                ForEach(FileKind.allCases, id: \.self) { kind in
                    Text(FilesStrings.kind(kind)).tag(FileKind?.some(kind))
                }
            } label: { Text(FilesStrings.kindFilter) }
            .frame(maxWidth: 220)

            Picker(selection: $model.ageFilter) {
                ForEach(LargeFilesModel.AgeFilter.allCases, id: \.self) { filter in
                    Text(FilesStrings.age(filter)).tag(filter)
                }
            } label: { Text(FilesStrings.ageFilter) }
            .frame(maxWidth: 260)
            Spacer()
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.xxs) {
                ForEach(model.visibleItems) { item in
                    row(item)
                }
            }
        }
    }

    private func row(_ item: ScanItem) -> some View {
        Toggle(isOn: Binding(get: { model.isSelected(item) }, set: { _ in model.toggle(item) })) {
            HStack(spacing: Spacing.xs) {
                Text(item.displayName).font(Typography.body).lineLimit(1)
                Text((item.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(Typography.path)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: Spacing.small)
                if let days = Self.daysSince(item.lastUsed) {
                    Text(FilesStrings.unused(days: days))
                        .font(Typography.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(item.size.formatted())
                    .numericStyle(Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
    }

    private var footer: some View {
        HStack {
            Text(FilesStrings.selected(count: model.selectedItems.count, size: model.selectedSize.formatted()))
                .font(Typography.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: model.scan) { Text(FilesStrings.rescan) }
            Button(action: model.prepareConfirmation) {
                Text(FilesStrings.trash).frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.selectedItems.isEmpty)
        }
    }

    private static func daysSince(_ date: Date?) -> Int? {
        date.map { max(0, Int(Date().timeIntervalSince($0) / 86_400)) }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3_600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? ""
    }
}

private struct IdentifiedPlan: Identifiable, Equatable {
    let plan: DeletionPlan
    var id: Int { plan.hashValue }
}
