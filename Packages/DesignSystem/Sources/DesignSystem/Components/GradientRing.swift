import SwiftUI

/// Animated progress ring — CLAUDE.md §5.4. Used for disk usage, scan progress and the health score.
public struct GradientRing: View {
    private let progress: Double
    private let palette: GradientPair
    private let lineWidth: CGFloat
    private let isIndeterminate: Bool

    @State private var spin: Double = 0

    @Environment(\.allowsDecorativeMotion) private var allowsDecorativeMotion

    /// - Parameters:
    ///   - progress: 0...1. Clamped, so a bad reading cannot draw an impossible ring.
    ///   - isIndeterminate: draws a rotating arc for work whose total is unknown (§8).
    public init(
        progress: Double,
        palette: GradientPair,
        lineWidth: CGFloat = 14,
        isIndeterminate: Bool = false
    ) {
        self.progress = min(1, max(0, progress))
        self.palette = palette
        self.lineWidth = lineWidth
        self.isIndeterminate = isIndeterminate
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: isIndeterminate ? 0.22 : progress)
                .stroke(
                    palette.angular,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90 + spin))
                .motion(Motion.smooth, value: progress)
        }
        .onAppear {
            guard isIndeterminate, allowsDecorativeMotion else { return }
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                spin = 360
            }
        }
        .accessibilityElement()
        .accessibilityValue(
            isIndeterminate
                ? Text(Strings.ringIndeterminate)
                : Text(progress.formatted(.percent.precision(.fractionLength(0))))
        )
    }
}

#Preview("GradientRing") {
    HStack(spacing: Spacing.large) {
        ForEach(AppSection.allCases.prefix(4)) { section in
            GradientRing(progress: 0.68, palette: section.palette)
                .frame(width: 90, height: 90)
        }
        GradientRing(progress: 0, palette: AppSection.smartScan.palette, isIndeterminate: true)
            .frame(width: 90, height: 90)
    }
    .padding(Spacing.xl)
}
