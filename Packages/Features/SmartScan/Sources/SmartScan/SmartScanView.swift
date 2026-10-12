import SwiftUI
import CoreKit
import DesignSystem
import ScanEngine

/// The scan screen — the app's signature moment (CLAUDE.md §5.5, §6.2).
///
/// Phase 1 drives this from a simulated run so the animation can be judged before real scanners
/// exist (Phase 4). The view takes a `ScanPhase` and knows nothing about where it came from.
public struct SmartScanView: View {
    private let phase: ScanPhase
    private let onStart: () -> Void
    private let onCancel: () -> Void
    private let onReview: (() -> Void)?

    private var section: AppSection { .smartScan }

    public init(
        phase: ScanPhase,
        onStart: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onReview: (() -> Void)? = nil
    ) {
        self.phase = phase
        self.onStart = onStart
        self.onCancel = onCancel
        self.onReview = onReview
    }

    public var body: some View {
        VStack(spacing: Spacing.large) {
            SectionHeader(
                title: SmartScanStrings.title,
                subtitle: SmartScanStrings.subtitle,
                palette: section.palette
            )

            // One centred stage holding the ring, its particle field and the status line.
            // Grouping them means the block centres as a unit instead of the ring drifting
            // upward as the status text changes height.
            VStack(spacing: Spacing.large) {
                ZStack {
                    if phase.isScanning {
                        ScanParticleField(palette: section.palette)
                            .frame(width: 400, height: 400)
                            .transition(.opacity)
                    }

                    ring
                }
                .frame(width: 400, height: 400)

                statusText
                    // Reserve the line so the ring does not shift when the text swaps.
                    .frame(minHeight: 44, alignment: .top)
            }
            .frame(maxHeight: .infinity)

            controls
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .motion(Motion.smooth, value: phase)
    }

    private var ring: some View {
        ZStack {
            GradientRing(
                progress: phase.progress?.fraction ?? (isComplete ? 1 : 0),
                palette: section.palette,
                lineWidth: 16,
                // Scanners that cannot report a total get the rotating arc instead (§8).
                isIndeterminate: phase.isScanning && phase.progress?.fraction == nil
            )
            .frame(width: 240, height: 240)

            VStack(spacing: Spacing.xxs) {
                Text(isComplete ? SmartScanStrings.ready : SmartScanStrings.found)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)

                AnimatedCounter(discoveredText, font: Typography.hero)

                Text(SmartScanStrings.itemsFound(itemCount))
                    .numericStyle(Typography.caption)
                    .foregroundStyle(.tertiary)
            }
            // Keep the readout inside the ring's inner diameter.
            .frame(maxWidth: 176)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch phase {
        case .scanning(let progress):
            // The folder currently being examined — §5.5. Monospaced so long paths stay readable.
            Text(progress.currentPath ?? "")
                .font(Typography.path)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520)

        case .finished(_, _, let additional, let needsPermission):
            VStack(spacing: Spacing.xxs) {
                Text(SmartScanStrings.finishedTitle)
                    .font(Typography.cardTitle)

                if !additional.isZero {
                    // Said plainly, so the headline is not mistaken for everything that was seen.
                    Text(SmartScanStrings.additional(additional.formatted()))
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
                if needsPermission {
                    Text(SmartScanStrings.permission)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
                // §4.6: say plainly that nothing was removed.
                Text(SmartScanStrings.finishedNote)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }

        case .cancelled:
            Text(SmartScanStrings.cancelled)
                .font(Typography.cardTitle)

        case .idle:
            // §6.2: be upfront that the heavy scanners are not part of this run.
            Text(SmartScanStrings.heavyHint)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if phase.canCancel {
            Button(role: .cancel, action: onCancel) {
                Text(SmartScanStrings.cancel)
                    .frame(minWidth: 120)
            }
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)
        } else if isComplete, let onReview {
            HStack(spacing: Spacing.medium) {
                Button(action: onReview) {
                    Text(SmartScanStrings.review).frame(minWidth: 160)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                Button(action: onStart) {
                    Text(SmartScanStrings.rescan)
                }
                .controlSize(.large)
            }
        } else {
            ScanButton(
                title: SmartScanStrings.idleAction,
                palette: section.textSafePalette,
                action: onStart
            )
        }
    }

    private var isComplete: Bool {
        if case .finished = phase { return true }
        return false
    }

    private var discoveredText: String {
        switch phase {
        case .idle, .cancelled: ByteCount.zero.formatted()
        case .scanning(let progress): progress.discovered.formatted()
        case .finished(let found, _, _, _): found.formatted()
        }
    }

    private var itemCount: Int {
        switch phase {
        case .idle, .cancelled: 0
        case .scanning(let progress): progress.itemCount
        case .finished(_, let count, _, _): count
        }
    }
}

#Preview("Idle") {
    SmartScanView(phase: .idle, onStart: {}, onCancel: {})
        .frame(width: 860, height: 760)
}

#Preview("Scanning") {
    SmartScanView(
        phase: .scanning(
            ScanProgress(
                fraction: 0.42,
                currentPath: "~/Library/Caches/com.apple.Safari/WebKitCache/Version 16",
                discovered: .gigabytes(8),
                itemCount: 1_284
            )
        ),
        onStart: {},
        onCancel: {}
    )
    .frame(width: 860, height: 760)
}

#Preview("Finished") {
    SmartScanView(
        phase: .finished(
            found: .gigabytes(6),
            itemCount: 157,
            additional: .gigabytes(13),
            needsPermission: true
        ),
        onStart: {},
        onCancel: {},
        onReview: {}
    )
    .frame(width: 860, height: 760)
}
