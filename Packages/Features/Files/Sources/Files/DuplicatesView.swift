import SwiftUI
import ImageIO
import AppKit
import CoreKit
import DesignSystem
import DeletionUI
import ScanEngine
import SafetyKit

/// The duplicate finder screen — CLAUDE.md §6.7.
public struct DuplicatesView: View {
    @State private var model: DuplicatesModel

    private var section: AppSection { .files }
    private var isSimilar: Bool { model.kind == .similar }

    public init(model: DuplicatesModel = DuplicatesModel()) {
        self._model = State(initialValue: model)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            SectionHeader(
                title: isSimilar ? FilesStrings.similarTitle : FilesStrings.dupTitle,
                subtitle: isSimilar ? FilesStrings.similarSubtitle : FilesStrings.dupSubtitle,
                palette: section.palette
            )

            switch model.phase {
            case .idle, .failed: idleState
            case .scanning(let progress, let remaining): scanningState(progress, remaining: remaining)
            case .reviewing(let wasCancelled): reviewState(wasCancelled: wasCancelled)
            case .deleting: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .finished(let report):
                DeletionResultView(report: report, section: section) { model.reset() }
            }
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
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
        VStack(spacing: Spacing.large) {
            Spacer()
            EmptyState(
                symbol: isSimilar ? "photo.on.rectangle" : "square.on.square",
                title: isSimilar ? FilesStrings.similarTitle : FilesStrings.dupTitle,
                message: isSimilar ? FilesStrings.similarSubtitle : FilesStrings.dupSubtitle
            )
            ScanButton(title: FilesStrings.scan, palette: section.textSafePalette, action: model.scan)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func scanningState(_ progress: ScanProgress, remaining: TimeInterval?) -> some View {
        VStack(spacing: Spacing.large) {
            Spacer()
            GradientRing(
                progress: progress.fraction ?? 0, palette: section.palette, lineWidth: 14,
                isIndeterminate: progress.fraction == nil
            )
            .frame(width: 180, height: 180)
            .overlay {
                // Look-alike scans measure no bytes while running; show how many pictures are done instead of "0 kB".
                AnimatedCounter(
                    progress.discovered.bytes > 0 ? progress.discovered.formatted() : "\(progress.itemCount)",
                    font: Typography.metric
                )
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

    private func reviewState(wasCancelled: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            if wasCancelled {
                Label { Text(FilesStrings.partial) } icon: { Image(systemName: "pause.circle") }
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
            if model.groups.isEmpty {
                VStack {
                    Spacer()
                    EmptyState(
                        symbol: "checkmark.circle",
                        title: isSimilar ? FilesStrings.similarEmptyTitle : FilesStrings.dupEmptyTitle,
                        message: isSimilar ? FilesStrings.similarEmptyDetail : FilesStrings.dupEmptyDetail
                    )
                    Spacer()
                }
            } else {
                rules
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.medium) {
                        ForEach(model.groups) { group in groupCard(group) }
                    }
                }
            }
            footer
        }
        .frame(maxHeight: .infinity)
    }

    private var rules: some View {
        HStack(spacing: Spacing.small) {
            Button { model.apply(.oldest) } label: { Text(FilesStrings.keepOldest) }
            if isSimilar {
                Button { model.apply(.largest) } label: { Text(FilesStrings.keepLargest) }
            }
            Button { model.apply(.shortestPath) } label: { Text(FilesStrings.keepShortest) }
            Button(action: model.clearSelection) { Text(FilesStrings.clearSelection) }
                .disabled(model.selection.isEmpty)
            Spacer()
            Text(FilesStrings.keepNote)
                .font(Typography.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func groupCard(_ group: ScanItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack {
                Text(group.displayName).font(Typography.body).lineLimit(1)
                Spacer()
                Text(FilesStrings.copies(group.children.count))
                    .font(Typography.caption).foregroundStyle(.tertiary)
                Text(FilesStrings.wasted(ByteCount(group.wasted).formatted()))
                    .numericStyle(Typography.caption).foregroundStyle(.secondary)
            }
            ForEach(group.children) { copy in
                Toggle(isOn: Binding(
                    get: { model.isSelected(copy) },
                    set: { _ in model.toggle(copy, in: group) }
                )) {
                    HStack(spacing: Spacing.xs) {
                        if isSimilar { Thumbnail(url: copy.url) }
                        Text((copy.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                            .font(Typography.path)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer(minLength: Spacing.small)
                        if isSimilar {
                            Text(copy.size.formatted()).numericStyle(Typography.caption).foregroundStyle(.secondary)
                        }
                        if let date = copy.lastUsed {
                            Text(date, format: .dateTime.year().month().day())
                                .font(Typography.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
        .padding(Spacing.small)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    private var footer: some View {
        HStack {
            Text(FilesStrings.selected(count: model.selectedItems.count, size: model.selectedSize.formatted()))
                .font(Typography.caption)
                .foregroundStyle(.secondary)
            Text("·").foregroundStyle(.tertiary)
            Text(FilesStrings.reclaimable(model.reclaimableSize.formatted()))
                .font(Typography.caption)
                .foregroundStyle(.tertiary)
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

/// A small preview, decoded off the main thread at thumbnail size so a list of large originals
/// does not hold them in memory.
private struct Thumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
        .accessibilityHidden(true)
        .task(id: url) {
            let url = url
            image = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceCreateThumbnailWithTransform: true,
                          kCGImageSourceThumbnailMaxPixelSize: 112
                      ] as CFDictionary) else { return nil }
                return NSImage(cgImage: cg, size: .zero)
            }.value
        }
    }
}
