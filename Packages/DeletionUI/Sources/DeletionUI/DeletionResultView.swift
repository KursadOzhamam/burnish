import SwiftUI
import CoreKit
import DesignSystem
import SafetyKit

/// What actually happened — CLAUDE.md §4.8 and §5.5.
///
/// The figure shown is space genuinely reclaimed: items that failed or were skipped are
/// excluded from it and listed separately, because inflating this number is exactly what
/// §10.4 forbids.
public struct DeletionResultView: View {
    let report: DeletionReport
    let section: AppSection
    let onDone: () -> Void

    public init(report: DeletionReport, section: AppSection, onDone: @escaping () -> Void) {
        self.report = report
        self.section = section
        self.onDone = onDone
    }

    @Environment(\.allowsDecorativeMotion) private var allowsDecorativeMotion
    @State private var hasAppeared = false

    public var body: some View {
        VStack(spacing: Spacing.large) {
            Spacer()

            Image(systemName: report.hasFailures ? "checkmark.circle.badge.questionmark" : "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(section.palette.linear)
                .symbolEffect(.bounce, value: hasAppeared)

            VStack(spacing: Spacing.xxs) {
                Text(DeletionStrings.resultTitle)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)

                AnimatedCounter(report.reclaimed.formatted(), font: Typography.hero)
                    .frame(maxWidth: 320)
            }

            if report.hasFailures {
                Text(DeletionStrings.failures(count: report.failures.count))
                    .font(Typography.caption)
                    .foregroundStyle(Semantic.warning.color)
            }

            if !report.restorable.isEmpty {
                Label {
                    Text(DeletionStrings.note)
                } icon: {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                .font(Typography.caption)
                .foregroundStyle(.secondary)
            }

            Button(action: onDone) {
                Text(DeletionStrings.done).frame(minWidth: 160)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard allowsDecorativeMotion else { return }
            hasAppeared = true
        }
    }
}
