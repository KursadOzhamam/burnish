import SwiftUI
import CoreKit
import DesignSystem
import SafetyKit
import SafetyKitMac

/// The history screen — CLAUDE.md §4.7: everything the app removed, with a way back for
/// whatever went to the Trash.
public struct HistoryView: View {
    @State private var model: HistoryModel
    @Environment(\.dismiss) private var dismiss

    public init(model: HistoryModel) {
        self._model = State(initialValue: model)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack(alignment: .top) {
                SectionHeader(
                    title: HistoryStrings.title,
                    subtitle: HistoryStrings.subtitle,
                    palette: AppSection.cleanup.palette
                )
                Button(action: { dismiss() }) {
                    Text(HistoryStrings.close)
                }
                .keyboardShortcut(.cancelAction)
            }

            if model.isAvailable {
                content
            } else {
                // Say so, rather than showing an empty list that looks like "nothing happened".
                Label {
                    Text(HistoryStrings.unavailable)
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(Semantic.warning.color)
                }
                .font(Typography.body)
                .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(Spacing.large)
        .frame(width: 640, height: 560)
        .task { model.reload() }
    }

    @ViewBuilder
    private var content: some View {
        if let notice = model.notice {
            noticeBanner(notice)
        }

        if model.records.isEmpty {
            EmptyState(symbol: "clock.arrow.circlepath", title: HistoryStrings.empty)
        } else {
            Text(HistoryStrings.reclaimed(model.totalReclaimed.formatted()))
                .numericStyle(Typography.cardTitle)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.records) { record in
                        row(record)
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }

    private func row(_ record: OperationRecord) -> some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayName)
                    .font(Typography.body)
                    .lineLimit(1)

                Text(Self.folder(of: record))
                    .font(Typography.path)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)

                HStack(spacing: Spacing.xs) {
                    Text(HistoryStrings.outcome(record.outcome))
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                    Text(record.performedAt, format: .dateTime.day().month().hour().minute())
                        .font(Typography.caption)
                        .foregroundStyle(.tertiary)
                }

                if record.outcome == .failed, let message = record.failureMessage {
                    Text(message)
                        .font(Typography.caption)
                        .foregroundStyle(Semantic.warning.color)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: Spacing.small)

            Text(record.size.formatted())
                .numericStyle(Typography.caption)
                .foregroundStyle(.secondary)

            if record.canRestore {
                Button(action: { model.restore(record) }) {
                    Text(HistoryStrings.restore)
                }
            } else if record.restoredAt != nil {
                Text(HistoryStrings.restoredBadge)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func noticeBanner(_ notice: HistoryModel.Notice) -> some View {
        HStack(spacing: Spacing.small) {
            switch notice {
            case .restored(let name):
                Image(systemName: "checkmark.circle").foregroundStyle(Semantic.success.color)
                Text(HistoryStrings.restored(name))
            case .failed(let failure):
                // A refusal is shown as plainly as a success: restoring never overwrites, and the
                // user should know why nothing moved.
                Image(systemName: "exclamationmark.circle").foregroundStyle(Semantic.warning.color)
                Text(HistoryStrings.message(for: failure))
            }
            Spacer(minLength: Spacing.small)
            Button(action: model.dismissNotice) {
                Text(HistoryStrings.dismiss)
            }
        }
        .font(Typography.caption)
        .padding(Spacing.small)
        // Same construction as the Cleanup banner, which collapsed the window layout when it
        // used `background(_:in:)`.
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.medium).fill(.quaternary)
        }
    }

    /// The containing folder with the home directory shown as `~`.
    private static func folder(of record: OperationRecord) -> String {
        (URL(fileURLWithPath: record.path).deletingLastPathComponent().path as NSString)
            .abbreviatingWithTildeInPath
    }
}
