import SwiftUI
import CoreKit
import DesignSystem
import ScanEngine
import SafetyKit
import SafetyKitMac
import DeletionUI

/// The Cleanup screen — CLAUDE.md §6.3.
///
/// The flow is deliberately linear: category cards, then the item list, then a confirmation
/// sheet that states exactly what will happen, then the result. Nothing is removed before the
/// sheet is approved (§4.6).
public struct CleanupView: View {
    @State private var model: CleanupModel

    private let section: AppSection
    private let title: LocalizedStringResource
    private let subtitle: LocalizedStringResource

    /// - Parameters:
    ///   - section: which section's colours and result screen this is shown under, so the same
    ///     review flow serves both Cleanup and Privacy.
    public init(
        model: CleanupModel = CleanupModel(),
        section: AppSection = .cleanup,
        title: LocalizedStringResource? = nil,
        subtitle: LocalizedStringResource? = nil
    ) {
        self._model = State(initialValue: model)
        self.section = section
        self.title = title ?? CleanupStrings.title
        self.subtitle = subtitle ?? CleanupStrings.subtitle
    }

    /// The Privacy screen: the same flow over browsing-trace scanners.
    public static func privacy(model: CleanupModel) -> CleanupView {
        CleanupView(
            model: model,
            section: .privacy,
            title: CleanupStrings.key("privacy.title"),
            subtitle: CleanupStrings.key("privacy.subtitle")
        )
    }

    public var body: some View {
        Group {
            if case .idle = model.phase {
                CleanupLanding(
                    model: model,
                    content: section == .privacy ? .privacy : .cleanup,
                    rules: section == .privacy ? CleanupCatalogue.Privacy.all : CleanupCatalogue.all,
                    onChange: { if section == .cleanup { model.updateScanners(CleanupScanner.enabled()) } }
                )
            } else {
                workflow
            }
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

    private var workflow: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            SectionHeader(
                title: title,
                subtitle: subtitle,
                palette: section.palette
            )

            switch model.phase {
            case .idle:
                idleState
            case .scanning(let progress):
                scanningState(progress)
            case .reviewing:
                reviewState
            case .deleting(let completed, let total):
                deletingState(completed: completed, total: total)
            case .finished(let report):
                DeletionResultView(report: report, section: section) { model.reset() }
            }
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pageBackground()
        .motion(Motion.smooth, value: model.openCategory)
    }

    // MARK: States

    private var idleState: some View {
        VStack(spacing: Spacing.large) {
            Spacer()
            EmptyState(
                symbol: "sparkle.magnifyingglass",
                title: CleanupStrings.title,
                message: CleanupStrings.subtitle
            )
            ScanButton(
                title: CleanupStrings.scanAction,
                palette: section.textSafePalette,
                action: model.scan
            )
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func scanningState(_ progress: ScanProgress) -> some View {
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

            Text(progress.currentPath ?? "")
                .font(Typography.path)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520, minHeight: 20)

            Button(role: .cancel, action: model.cancel) {
                Text(CleanupStrings.cancel).frame(minWidth: 110)
            }
            .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var reviewState: some View {
        if model.categories.isEmpty {
            VStack {
                Spacer()
                EmptyState(
                    symbol: "checkmark.circle",
                    title: CleanupStrings.nothingFound,
                    message: CleanupStrings.nothingFoundDetail
                )
                Spacer()
            }
        } else {
            // One self-contained block with a bounded height. As three loose siblings of the
            // outer stack, a list taller than the window (nine categories) was laid out at its
            // full height, which pushed the header, sidebar and footer out of the window.
            VStack(spacing: Spacing.medium) {
                if model.needsPermission {
                    permissionBanner
                }
                ScrollView {
                    LazyVStack(spacing: Spacing.medium) {
                        ForEach(model.categories) { category in
                            CategoryCard(
                                category: category,
                                isExpanded: model.openCategory == category.id,
                                model: model,
                                onToggleExpanded: {
                                    model.openCategory = model.openCategory == category.id
                                        ? nil
                                        : category.id
                                }
                            )
                        }
                    }
                    .padding(.bottom, Spacing.xl)
                }
                .frame(maxHeight: .infinity)
                reviewFooter
            }
            .frame(maxHeight: .infinity)
        }
    }

    /// Says plainly that some folders could not be read, instead of letting them look empty.
    private var permissionBanner: some View {
        // Written without `fixedSize` and without `background(_:in:)`. The first version used both
        // and, with a long localized message, collapsed the layout of the whole window: header,
        // sidebar and footer disappeared. Found by running the app, bisected by swapping the
        // cards for plain text and then disabling only this banner.
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.secondary)
            Text(CleanupStrings.permissionBanner)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: model.openFullDiskAccessSettings) {
                Text(CleanupStrings.permissionOpen)
            }
        }
        .padding(Spacing.small)
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.medium).fill(.quaternary)
        }
    }

    private var reviewFooter: some View {
        HStack(spacing: Spacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    CleanupStrings.selected(
                        count: model.selectedItems.count,
                        size: model.selectedSize.formatted()
                    )
                )
                .numericStyle(Typography.cardTitle)

                if model.blockedCount > 0 {
                    // Say what was left out and why, rather than quietly dropping it (§4.8).
                    Text(CleanupStrings.skipped(count: model.blockedCount))
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: model.reset) {
                Text(CleanupStrings.cancel)
            }
            .controlSize(.large)

            Button(action: model.prepareConfirmation) {
                Text(CleanupStrings.reviewAction).frame(minWidth: 140)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(model.selectedItems.isEmpty)
        }
        .padding(.top, Spacing.xs)
    }

    private func deletingState(completed: Int, total: Int) -> some View {
        VStack(spacing: Spacing.large) {
            Spacer()
            GradientRing(
                progress: total > 0 ? Double(completed) / Double(total) : 0,
                palette: section.palette,
                lineWidth: 14,
                isIndeterminate: true
            )
            .frame(width: 140, height: 140)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Wraps a plan so it can drive a `sheet(item:)`.
private struct IdentifiedPlan: Identifiable {
    let plan: DeletionPlan
    var id: Int { plan.hashValue }

    init(_ plan: DeletionPlan) { self.plan = plan }
}

#Preview("Cleanup — idle") {
    CleanupView()
        .frame(width: 900, height: 700)
}
