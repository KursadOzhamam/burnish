import SwiftUI

/// A number that eases to its new value — CLAUDE.md §5.4, via `contentTransition(.numericText())`.
///
/// Drives the "space found" counter on the scan screen (§5.5).
public struct AnimatedCounter: View {
    private let text: String
    private let font: Font

    public init(_ text: String, font: Font = Typography.metric) {
        self.text = text
        self.font = font
    }

    public var body: some View {
        Text(text)
            .numericStyle(font)
            .contentTransition(.numericText())
            .lineLimit(1)
            // A counter sits inside fixed containers such as the scan ring, and the value grows
            // as a scan runs ("9 GB" to "118,4 GB"). Shrink rather than overflow or truncate.
            .minimumScaleFactor(0.5)
            .motion(Motion.smooth, value: text)
    }
}

#Preview("AnimatedCounter") {
    @Previewable @State var value = 14

    return VStack(spacing: Spacing.large) {
        AnimatedCounter("\(value) GB", font: Typography.hero)
        Button("Add") { value += 7 }
    }
    .padding(Spacing.xl)
}
