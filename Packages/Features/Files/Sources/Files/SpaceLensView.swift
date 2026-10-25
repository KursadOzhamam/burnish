import SwiftUI
import CoreKit
import DesignSystem
import DeletionUI
import ScanEngine
import SafetyKit

/// The Space Lens screen — CLAUDE.md §6.7.
public struct SpaceLensView: View {
    @State private var model: SpaceLensModel
    @Environment(\.colorScheme) private var scheme

    private var section: AppSection { .files }

    public init(model: SpaceLensModel = SpaceLensModel()) {
        self._model = State(initialValue: model)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            SectionHeader(title: FilesStrings.mapTitle, subtitle: FilesStrings.mapSubtitle, palette: section.palette)

            switch model.phase {
            case .idle: idleState
            case .scanning(let progress, let remaining): scanningState(progress, remaining: remaining)
            case .reviewing: reviewState
            case .failed: idleState
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

    // MARK: States

    private var idleState: some View {
        VStack(spacing: Spacing.large) {
            Spacer()
            StatusRing(symbol: "chart.pie", title: "", diameter: 150)
            Text(FilesStrings.mapHint)
                .font(.system(size: 14))
                .foregroundStyle(scheme.theme.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Picker(selection: Binding(get: { model.root }, set: { model.root = $0 })) {
                ForEach(model.rootOptions, id: \.path) { url in
                    Text(url.path == FileManager.default.homeDirectoryForCurrentUser.path
                         ? String(localized: FilesStrings.mapHome) : url.lastPathComponent).tag(url)
                }
            } label: { Text(FilesStrings.mapRoot) }
            .frame(maxWidth: 320)
            ScanButton(title: FilesStrings.scan, palette: section.textSafePalette, action: model.scan)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func scanningState(_ progress: ScanProgress, remaining: TimeInterval?) -> some View {
        VStack(spacing: Spacing.large) {
            Spacer()
            GradientRing(progress: 0, palette: section.palette, lineWidth: 14, isIndeterminate: true)
                .frame(width: 180, height: 180)
                .overlay {
                    AnimatedCounter(progress.discovered.formatted(), font: Typography.metric)
                        .frame(maxWidth: 130)
                }
            Text(FilesStrings.found(count: progress.itemCount))
                .font(Typography.caption)
                .foregroundStyle(.secondary)
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

    @ViewBuilder
    private var reviewState: some View {
        if let focus = model.focus {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                breadcrumb
                HStack(alignment: .top, spacing: Spacing.large) {
                    SunburstView(focus: focus, model: model, palette: section)
                        .frame(minWidth: 320, idealWidth: 420, maxWidth: 480)
                        .aspectRatio(1, contentMode: .fit)
                    childList(of: focus)
                }
                .frame(maxHeight: .infinity)
                footer
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: Spacing.xs) {
            if model.breadcrumb.count > 1 {
                Button(action: model.zoomOut) {
                    Label { Text(FilesStrings.mapUp) } icon: { Image(systemName: "chevron.up") }
                }
                .buttonStyle(.borderless)
            }
            ForEach(Array(model.breadcrumb.enumerated()), id: \.offset) { index, item in
                if index > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                Button(Self.name(of: item)) { model.zoom(toLevel: index) }
                    .buttonStyle(.borderless)
                    .font(Typography.caption)
                    .disabled(index == model.breadcrumb.count - 1)
            }
            Spacer()
        }
    }

    private func childList(of focus: ScanItem) -> some View {
        ScrollView {
            LazyVStack(spacing: Spacing.xxs) {
                ForEach(focus.children) { item in
                    row(item, parentTotal: focus.totalSize)
                }
            }
        }
    }

    private func row(_ item: ScanItem, parentTotal: ByteCount) -> some View {
        let percent = parentTotal.bytes > 0 ? Int((Double(item.totalSize.bytes) / Double(parentTotal.bytes) * 100).rounded()) : 0
        return HStack(spacing: Spacing.xs) {
            if item.isActionable {
                Toggle(isOn: Binding(get: { model.isSelected(item) }, set: { _ in model.toggle(item) })) { EmptyView() }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            } else {
                Color.clear.frame(width: 16, height: 16)
            }
            Button {
                model.zoom(into: item)
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: item.children.isEmpty ? "doc" : "folder")
                        .foregroundStyle(.secondary)
                    Text(Self.name(of: item)).font(Typography.body).lineLimit(1)
                    Spacer(minLength: Spacing.small)
                    Text("\(percent)%").font(Typography.caption).foregroundStyle(.tertiary)
                    Text(item.totalSize.formatted()).numericStyle(Typography.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canZoom(into: item))
        }
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

    static func name(of item: ScanItem) -> String {
        if item.displayName.isEmpty && item.blockedReason == .outsideScope {
            return String(localized: FilesStrings.mapOther)
        }
        if item.blockedReason == .needsFullDiskAccess {
            return "\(item.url.lastPathComponent) · " + String(localized: FilesStrings.mapUnreadable)
        }
        return item.url.lastPathComponent
    }
}

/// The ring map itself. Drawn in one `Canvas` so thousands of arcs stay cheap.
private struct SunburstView: View {
    let focus: ScanItem
    let model: SpaceLensModel
    let palette: AppSection

    private let rings = 4

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let inner = side * 0.16
            let ringWidth = (side / 2 - inner) / CGFloat(rings)
            let arcs = SunburstLayout.arcs(for: focus, maxDepth: rings)

            ZStack {
                Canvas { context, _ in
                    for arc in arcs {
                        let radius = inner + ringWidth * CGFloat(arc.depth)
                        var path = Path()
                        path.addArc(
                            center: center, radius: radius + ringWidth - 1,
                            startAngle: .degrees(arc.start * 360 - 90), endAngle: .degrees(arc.end * 360 - 90),
                            clockwise: false
                        )
                        path.addArc(
                            center: center, radius: radius + 1,
                            startAngle: .degrees(arc.end * 360 - 90), endAngle: .degrees(arc.start * 360 - 90),
                            clockwise: true
                        )
                        path.closeSubpath()
                        let isHovered = model.hovered?.id == arc.item.id
                        context.fill(path, with: .color(color(for: arc, among: arcs, hovered: isHovered)))
                    }
                }
                .drawingGroup()
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        model.hovered = SunburstLayout.arc(
                            at: point, center: center, innerRadius: inner, ringWidth: ringWidth, in: arcs
                        )?.item
                    case .ended:
                        model.hovered = nil
                    }
                }
                .gesture(
                    SpatialTapGesture().onEnded { tap in
                        guard let hit = SunburstLayout.arc(
                            at: tap.location, center: center, innerRadius: inner, ringWidth: ringWidth, in: arcs
                        ) else {
                            model.zoomOut()
                            return
                        }
                        model.zoom(into: hit.item)
                    }
                )

                VStack(spacing: 2) {
                    let shown = model.hovered ?? focus
                    Text(SpaceLensView.name(of: shown))
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(shown.totalSize.formatted())
                        .numericStyle(Typography.metric)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(width: inner * 1.7)
                .allowsHitTesting(false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(SpaceLensView.name(of: focus)))
            .accessibilityValue(Text(focus.totalSize.formatted()))
        }
    }

    /// Hue by top-level branch so a branch keeps one colour as you look deeper; lighter outward.
    private func color(for arc: SunburstArc, among arcs: [SunburstArc], hovered: Bool) -> Color {
        if arc.isOtherBlock { return Color.gray.opacity(0.35) }
        if arc.item.blockedReason == .needsFullDiskAccess { return Color.gray.opacity(0.5) }
        let topLevel = arcs.last { $0.depth == 0 && $0.start <= arc.start + 1e-9 }
        let hue = topLevel.map { ($0.start + $0.end) / 2 } ?? 0.6
        let brightness = max(0.45, 0.85 - Double(arc.depth) * 0.1) + (hovered ? 0.12 : 0)
        return Color(hue: hue, saturation: 0.55, brightness: min(1, brightness))
    }
}

private struct IdentifiedPlan: Identifiable, Equatable {
    let plan: DeletionPlan
    var id: Int { plan.hashValue }
}
