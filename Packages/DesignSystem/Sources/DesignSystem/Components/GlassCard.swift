import SwiftUI

/// Flat container (the design uses white cards with a hairline border, not frosted glass) — CLAUDE.md §5.4: hover grows it by 2% and deepens the shadow.
///
/// The material is only a background layer and the geometry is ours, so the card looks the same
/// across macOS releases (§5.2).
public struct GlassCard<Content: View>: View {
    @Environment(\.allowsDecorativeMotion) private var allowsDecorativeMotion

    private let cornerRadius: CGFloat
    private let padding: CGFloat
    private let isInteractive: Bool
    private let content: Content

    @State private var isHovering = false

    public init(
        cornerRadius: CGFloat = CornerRadius.large,
        padding: CGFloat = Spacing.medium,
        isInteractive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.isInteractive = isInteractive
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(radius: min(cornerRadius, 20))
            .shadow(color: .black.opacity(isRaised ? 0.08 : 0.025), radius: isRaised ? 12 : 4, y: isRaised ? 5 : 1)
            .scaleEffect(isRaised ? 1.01 : 1)
            .motion(Motion.snappy, value: isRaised)
            .onHover { hovering in
                // Hover is a pointer concept; on iOS this closure simply never fires.
                guard isInteractive else { return }
                isHovering = hovering
            }
    }

    /// Hover lift is decorative, so Reduce Motion suppresses it entirely rather than shortening it.
    private var isRaised: Bool {
        isInteractive && isHovering && allowsDecorativeMotion
    }
}

#Preview("GlassCard") {
    VStack(spacing: Spacing.large) {
        GlassCard {
            Text("Static card").font(Typography.cardTitle)
        }
        GlassCard(isInteractive: true) {
            Text("Interactive — hover me").font(Typography.cardTitle)
        }
    }
    .padding(Spacing.xl)
    .frame(width: 360)
    .background(AppSection.dashboard.palette.linear)
}
