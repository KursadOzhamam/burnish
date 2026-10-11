import SwiftUI

/// Frosted container — CLAUDE.md §5.4: hover grows it by 2% and deepens the shadow.
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
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            }
            .overlay {
                // Hairline edge gives the card a defined boundary on busy backdrops.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: .black.opacity(isRaised ? 0.28 : 0.16),
                radius: isRaised ? 20 : 10,
                y: isRaised ? 8 : 4
            )
            .scaleEffect(isRaised ? 1.02 : 1)
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
