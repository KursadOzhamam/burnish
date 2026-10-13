import SwiftUI

/// An explicit sRGB colour.
///
/// Stored as components rather than as `Color` so palettes are inspectable and testable, and so
/// the brand's colours are defined by us rather than inherited from whatever the system
/// currently ships (CLAUDE.md §5.2).
public struct RGB: Sendable, Hashable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = min(1, max(0, red))
        self.green = min(1, max(0, green))
        self.blue = min(1, max(0, blue))
    }

    /// Convenience for authoring from hex, e.g. `RGB(hex: 0x4F46E5)`.
    public init(hex: UInt32) {
        self.init(
            Double((hex >> 16) & 0xFF) / 255,
            Double((hex >> 8) & 0xFF) / 255,
            Double(hex & 0xFF) / 255
        )
    }

    public var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    /// Relative luminance per WCAG 2.1, used by the contrast tests.
    public var luminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG contrast ratio against another colour, from 1 to 21.
    public func contrastRatio(against other: RGB) -> Double {
        let lhs = luminance
        let rhs = other.luminance
        return (max(lhs, rhs) + 0.05) / (min(lhs, rhs) + 0.05)
    }
}

/// A two-stop brand gradient.
public struct GradientPair: Sendable, Hashable {
    public let start: RGB
    public let end: RGB

    public init(start: RGB, end: RGB) {
        self.start = start
        self.end = end
    }

    public var linear: LinearGradient {
        LinearGradient(
            colors: [start.color, end.color],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Sweep used by progress rings, which need the gradient to travel around the circle.
    public var angular: AngularGradient {
        AngularGradient(
            colors: [start.color, end.color, start.color],
            center: .center
        )
    }

    /// Representative single colour for icons and text tints.
    public var representative: Color { start.color }

    /// Lowest WCAG contrast ratio this pair offers against `other`, i.e. the worst case anywhere
    /// along the gradient. Used by the contrast tests.
    public func minimumContrastRatio(against other: RGB) -> Double {
        min(start.contrastRatio(against: other), end.contrastRatio(against: other))
    }
}

/// Top-level areas of the app, each with its own gradient (CLAUDE.md §5.3).
///
/// Lives in DesignSystem because the palette is keyed by it; navigation uses the same enum so a
/// section and its colour can never drift apart.
public enum AppSection: String, Sendable, Hashable, CaseIterable, Identifiable {
    case dashboard
    case smartScan
    case cleanup
    case protection
    case performance
    case applications
    case files
    case privacy

    public var id: String { rawValue }

    /// SF Symbol for the sidebar. Matches the supplied design.
    public var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .smartScan: "sparkles"
        case .cleanup: "magnifyingglass.circle"
        case .protection: "shield"
        case .performance: "gauge.with.dots.needle.33percent"
        case .applications: "macwindow"
        case .files: "chart.pie"
        case .privacy: "hand.raised"
        }
    }

    /// Brand gradient for rings, sparklines and icon tints.
    ///
    /// The design uses one violet for every section, so every section returns the same pair.
    /// The API stays per-section so a later redesign can differentiate them again without
    /// touching call sites.
    public var palette: GradientPair { Brand.pair }

    /// Gradient for surfaces that carry text, e.g. a filled button. White on this violet is
    /// 6.2:1, above WCAG AA (§5.3); `PaletteContrastTests` guards it.
    public var textSafePalette: GradientPair { Brand.pair }
}

/// Foreground colours guaranteed against `textSafePalette`.
public enum Palette {
    /// The only foreground approved for text-bearing gradient fills.
    public static let onColor = RGB(hex: 0xFFFFFF)

    /// Brand ink for light surfaces, softer than pure black.
    public static let ink = RGB(hex: 0x0B1020)

    /// WCAG AA threshold for normal-sized text.
    public static let minimumContrast: Double = 4.5
}

/// Semantic colours that are not section-specific.
public enum Semantic {
    /// Reserved for genuine threats only. CLAUDE.md §10.3 forbids using alarm colour for
    /// ordinary findings.
    public static let danger = RGB(hex: 0xDC2626)
    public static let warning = RGB(hex: 0xF59E0B)
    public static let success = RGB(hex: 0x16A34A)
    /// Purgeable and other space that is not a real reclaimable gain (§10.4).
    public static let neutral = RGB(hex: 0x6B7280)
}
