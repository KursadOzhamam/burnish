import SwiftUI

/// Large breathing primary action — CLAUDE.md §5.4.
///
/// The breathing pulse is decorative, so it stops entirely under Reduce Motion (§5.3).
///
/// Takes a `textSafePalette`, never a decorative one: the label sits on the fill, so the pair
/// has to clear WCAG AA at both stops (§5.3).
public struct ScanButton: View {
    private let title: LocalizedStringResource
    private let palette: GradientPair
    private let isBusy: Bool
    private let action: () -> Void

    @Environment(\.allowsDecorativeMotion) private var allowsDecorativeMotion
    @State private var isPulsing = false

    public init(
        title: LocalizedStringResource,
        palette: GradientPair = AppSection.smartScan.textSafePalette,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.palette = palette
        self.isBusy = isBusy
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: isBusy ? "stop.fill" : "sparkles")
                    .symbolEffect(.pulse, isActive: isBusy)
                Text(title)
                    .font(Typography.cardTitle)
            }
            .padding(.horizontal, Spacing.large)
            .padding(.vertical, Spacing.small)
            .frame(minWidth: 220)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.onColor.color)
        .background {
            Capsule().fill(palette.linear)
        }
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .clipShape(Capsule())
        .shadow(color: palette.start.color.opacity(0.45), radius: isPulsing ? 22 : 12, y: 6)
        .scaleEffect(isPulsing ? 1.015 : 1)
        .onAppear {
            guard allowsDecorativeMotion, !isBusy else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .accessibilityHint(Text(Strings.scanButtonHint))
    }
}

#Preview("ScanButton") {
    VStack(spacing: Spacing.large) {
        ScanButton(title: "Smart Scan") {}
        ScanButton(
            title: "Clean up",
            palette: AppSection.cleanup.textSafePalette
        ) {}
        ScanButton(title: "Stop", isBusy: true) {}
    }
    .padding(Spacing.xxl)
}
