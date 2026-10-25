import SwiftUI

/// The one page background of the design, used by every full-screen view so the app is a single
/// surface whichever section is open (CLAUDE.md §5.1). Replaces `.background(.background)`, which
/// drew the system window colour and left inner screens looking unlike the landing pages.
public struct PageBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    public func body(content: Content) -> some View {
        content.background(scheme.theme.background.ignoresSafeArea())
    }
}

extension View {
    /// Fills the view with the design's page background in both appearances.
    public func pageBackground() -> some View { modifier(PageBackground()) }

    /// Standard page insets: a wide side gutter, a small top gap under the title bar and room at
    /// the bottom. Matches the landing pages so no section feels laid out differently.
    public func pageInsets() -> some View {
        padding(.horizontal, 32).padding(.top, 20).padding(.bottom, 24)
    }
}
