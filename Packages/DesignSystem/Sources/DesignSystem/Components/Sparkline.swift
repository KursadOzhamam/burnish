import SwiftUI

/// Compact trend line drawn with `Canvas`.
///
/// Hand-drawn rather than charted because it renders at tile size inside live metric cards that
/// refresh every second (§8); `drawingGroup()` keeps it off the main-thread layout path (§5.5).
public struct Sparkline: View {
    private let values: [Double]
    private let palette: GradientPair

    public init(values: [Double], palette: GradientPair) {
        self.values = values
        self.palette = palette
    }

    public var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }

            let lowest = values.min() ?? 0
            let highest = values.max() ?? 1
            // Flat series would divide by zero; give them a mid-height line instead.
            let span = highest - lowest
            let stepX = size.width / CGFloat(values.count - 1)

            func point(_ index: Int) -> CGPoint {
                let normalized = span > 0 ? (values[index] - lowest) / span : 0.5
                return CGPoint(
                    x: CGFloat(index) * stepX,
                    y: size.height - CGFloat(normalized) * size.height
                )
            }

            var line = Path()
            line.move(to: point(0))
            for index in 1..<values.count {
                line.addLine(to: point(index))
            }

            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()

            context.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [
                        palette.start.color.opacity(0.35),
                        palette.end.color.opacity(0.02)
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            context.stroke(
                line,
                with: .linearGradient(
                    Gradient(colors: [palette.start.color, palette.end.color]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                ),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

#Preview("Sparkline") {
    VStack {
        Sparkline(
            values: (0..<60).map { _ in Double.random(in: 20...80) },
            palette: AppSection.performance.palette
        )
        .frame(height: 44)

        Sparkline(values: Array(repeating: 50, count: 20), palette: AppSection.cleanup.palette)
            .frame(height: 44)
    }
    .padding(Spacing.xl)
}
