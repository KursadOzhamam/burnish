import SwiftUI

/// The surface and ink colours of the design, for both appearances.
///
/// Values are measured from the supplied design files (light) with a dark counterpart derived
/// from the same hue family. Components read the current colour scheme and ask for `ThemeColors`,
/// so nothing hard-codes a colour and the whole app switches together (CLAUDE.md §5.1).
public struct ThemeColors: Sendable {
    public let background: Color
    public let sidebar: Color
    public let card: Color
    public let cardBorder: Color
    public let hero: Color
    public let heroBorder: Color
    public let selection: Color
    public let ink: Color
    public let inkSecondary: Color
    public let inkTertiary: Color
    public let divider: Color
    public let accent: Color
    public let accentSoft: Color
    public let track: Color

    public static func `for`(_ scheme: ColorScheme) -> ThemeColors {
        scheme == .dark ? dark : light
    }

    public static let light = ThemeColors(
        background: RGB(hex: 0xF8F9FB).color,
        sidebar: RGB(hex: 0xF0F1F5).color,
        card: RGB(hex: 0xFFFFFF).color,
        cardBorder: RGB(hex: 0xE8EAF0).color,
        hero: RGB(hex: 0xF5F2FC).color,
        heroBorder: RGB(hex: 0xE9E3F5).color,
        selection: RGB(hex: 0xEAE5FA).color,
        ink: RGB(hex: 0x23232F).color,
        inkSecondary: RGB(hex: 0x6E6E7C).color,
        inkTertiary: RGB(hex: 0x9A9AA8).color,
        divider: RGB(hex: 0xECEDF2).color,
        accent: Brand.accent.color,
        accentSoft: RGB(hex: 0xE6DEFA).color,
        track: RGB(hex: 0xE7E2F6).color
    )

    public static let dark = ThemeColors(
        background: RGB(hex: 0x111218).color,
        sidebar: RGB(hex: 0x161821).color,
        card: RGB(hex: 0x1C1E28).color,
        cardBorder: RGB(hex: 0x2A2D3A).color,
        hero: RGB(hex: 0x1F1B33).color,
        heroBorder: RGB(hex: 0x39325E).color,
        selection: RGB(hex: 0x2C2552).color,
        ink: RGB(hex: 0xF3F3F8).color,
        inkSecondary: RGB(hex: 0xA3A5B4).color,
        inkTertiary: RGB(hex: 0x74768A).color,
        divider: RGB(hex: 0x262836).color,
        accent: Brand.accentOnDark.color,
        accentSoft: RGB(hex: 0x3A2F6B).color,
        track: RGB(hex: 0x35305A).color
    )
}

/// The one brand colour (the supplied design uses a single violet throughout).
public enum Brand {
    /// Ring strokes, the floating button, selected states, links.
    public static let accent = RGB(hex: 0x7044E8)
    /// A lighter step for dark surfaces, where the base violet loses contrast.
    public static let accentOnDark = RGB(hex: 0x9170F2)
    /// Second stop of the button gradient. Close to `accent` on purpose: the design is flat.
    public static let accentEnd = RGB(hex: 0x7C55EE)

    public static let pair = GradientPair(start: accent, end: accentEnd)
}

extension ColorScheme {
    public var theme: ThemeColors { ThemeColors.for(self) }
}
