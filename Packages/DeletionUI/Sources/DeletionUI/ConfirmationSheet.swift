import SwiftUI
import CoreKit
import DesignSystem
import ScanEngine
import SafetyKit

/// The last thing between a plan and the filesystem — CLAUDE.md §5.4 and §4.6.
///
/// It must be impossible to leave this sheet uncertain about three things: how much is going,
/// how many items that is, and whether it can be undone. Items skipped by the safety layer are
/// shown here too, with their reason, rather than disappearing silently.
public struct ConfirmationSheet: View {
    let plan: DeletionPlan
    let section: AppSection
    let canRecordHistory: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    public init(
        plan: DeletionPlan,
        section: AppSection,
        canRecordHistory: Bool,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.plan = plan
        self.section = section
        self.canRecordHistory = canRecordHistory
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            SectionHeader(title: DeletionStrings.title, palette: section.palette)

            headline

            reversibilityNote

            if !canRecordHistory {
                Label {
                    Text(DeletionStrings.noHistory)
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(Semantic.warning.color)
                }
                .font(Typography.caption)
                .foregroundStyle(.secondary)
            }

            if !plan.skipped.isEmpty {
                skippedSummary
            }

            Divider()

            itemList

            footer
        }
        .padding(Spacing.large)
        .frame(width: 560)
        .frame(maxHeight: 620)
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text(plan.totalSize.formatted())
                .numericStyle(Typography.hero)
                .foregroundStyle(section.palette.linear)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(DeletionStrings.summary(count: plan.itemCount, size: plan.totalSize.formatted()))
                .font(Typography.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var reversibilityNote: some View {
        if plan.mode.isIrreversible {
            Label {
                Text(DeletionStrings.permanentWarning)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Semantic.danger.color)
            }
            .font(Typography.body)
        } else {
            Label {
                Text(DeletionStrings.note)
            } icon: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .foregroundStyle(.secondary)
            }
            .font(Typography.body)
            .foregroundStyle(.secondary)
        }
    }

    private var skippedSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(groupedSkips, id: \.reason) { group in
                Text("\(group.count) · ")
                    .font(Typography.caption)
                    .foregroundStyle(.tertiary)
                + Text(DeletionStrings.reason(for: group.reason))
                    .font(Typography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var itemList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                ForEach(plan.items.sorted { $0.totalSize > $1.totalSize }) { item in
                    HStack(spacing: Spacing.xs) {
                        // Name plus its folder: "Adobe" alone appears under both Caches and
                        // Logs, and the sheet exists so the user can tell exactly what goes.
                        Text(item.displayName)
                            .font(Typography.body)
                            .lineLimit(1)
                        Text(Self.location(of: item))
                            .font(Typography.path)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer(minLength: Spacing.small)
                        Text(item.totalSize.formatted())
                            .numericStyle(Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxHeight: 240)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(action: onCancel) {
                Text(DeletionStrings.cancel)
            }
            .keyboardShortcut(.cancelAction)
            .controlSize(.large)

            Button(role: plan.mode.isIrreversible ? .destructive : nil, action: onConfirm) {
                Text(
                    plan.mode.isIrreversible
                        ? DeletionStrings.deletePermanently
                        : DeletionStrings.moveToTrash
                )
                .frame(minWidth: 140)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            // Permanent deletion is never the default action: §10.6 rules out making the
            // destructive choice the easy one.
            .keyboardShortcut(plan.mode.isIrreversible ? .noAction : .defaultAction)
        }
    }

    /// The containing folder with the home directory shown as `~`.
    private static func location(of item: ScanItem) -> String {
        (item.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }

    private var groupedSkips: [(reason: ScanItem.BlockedReason, count: Int)] {
        Dictionary(grouping: plan.skipped) { $0.blockedReason ?? .outsideScope }
            .map { (reason: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }
}

private extension KeyboardShortcut {
    /// No shortcut, used where a destructive button must not respond to Return.
    static let noAction = KeyboardShortcut("\u{F8FF}", modifiers: [.command, .option, .control])
}
