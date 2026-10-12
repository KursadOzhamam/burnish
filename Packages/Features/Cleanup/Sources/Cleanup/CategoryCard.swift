import SwiftUI
import CoreKit
import DesignSystem
import ScanEngine

/// One scanner's findings, collapsed to a card and expandable to a list.
struct CategoryCard: View {
    let category: CleanupModel.Category
    let isExpanded: Bool
    let model: CleanupModel
    let onToggleExpanded: () -> Void

    private var section: AppSection { .cleanup }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.small) {
                header

                if isExpanded {
                    Divider()
                    itemList
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            Toggle(
                isOn: Binding(
                    get: { isFullySelected },
                    set: { model.setSelection($0, in: category) }
                )
            ) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(category.actionable.isEmpty)

            VStack(alignment: .leading, spacing: 2) {
                Text(CleanupStrings.key(category.rule.titleKey))
                    .font(Typography.cardTitle)

                // Every category says what it is in plain language. §6.5 asks for this on
                // maintenance tasks; it matters at least as much where files are deleted.
                Text(CleanupStrings.key(category.rule.explanationKey))
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.small)

            VStack(alignment: .trailing, spacing: 2) {
                if category.actionable.isEmpty {
                    // Everything here was found but cannot be acted on. Showing "0 kB" would
                    // claim nothing was found; show what exists and say it is being skipped.
                    Text(category.items.totalSize().formatted())
                        .numericStyle(Typography.cardTitle)
                        .foregroundStyle(.secondary)

                    Text(CleanupStrings.skipped(count: category.items.count))
                        .font(Typography.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else {
                    Text(category.totalSize.formatted())
                        .numericStyle(Typography.cardTitle)
                        .foregroundStyle(section.palette.linear)

                    Text(
                        CleanupStrings.summary(
                            count: category.actionable.count,
                            size: category.totalSize.formatted()
                        )
                    )
                    .font(Typography.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }
            }

            Button(action: onToggleExpanded) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private var itemList: some View {
        VStack(spacing: 0) {
            ForEach(sortedItems) { item in
                ItemRow(item: item, model: model)
                if item.id != sortedItems.last?.id {
                    Divider().opacity(0.4)
                }
            }
        }
    }

    /// Largest first: the user's attention belongs on what actually matters.
    private var sortedItems: [ScanItem] {
        category.items.sorted { $0.totalSize > $1.totalSize }
    }

    private var isFullySelected: Bool {
        !category.actionable.isEmpty
            && category.actionable.allSatisfy { model.isSelected($0) }
    }
}

/// One finding.
private struct ItemRow: View {
    let item: ScanItem
    let model: CleanupModel

    var body: some View {
        HStack(spacing: Spacing.small) {
            Toggle(
                isOn: Binding(
                    get: { model.isSelected(item) },
                    set: { _ in model.toggle(item) }
                )
            ) { EmptyView() }
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(!item.isActionable)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .font(Typography.body)
                    .foregroundStyle(item.isActionable ? .primary : .secondary)
                    .lineLimit(1)

                if let reason = item.blockedReason {
                    // Name the real reason. Reporting a protected path as "you excluded this"
                    // would be untrue, and §10 rules that out.
                    Text(CleanupStrings.reason(for: reason))
                        .font(Typography.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(item.url.path)
                        .font(Typography.path)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: Spacing.small)

            Text(item.totalSize.formatted())
                .numericStyle(Typography.caption)
                .foregroundStyle(item.isActionable ? .secondary : .tertiary)
        }
        .padding(.vertical, Spacing.xxs)
        .opacity(item.isActionable ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }
}
