import SwiftUI

/// Type tokens — CLAUDE.md §5.3: SF Pro, with `.rounded` and `monospacedDigit()` for large numbers.
public enum Typography {
    /// Hero number, e.g. the health score or reclaimed space.
    public static let hero = Font.system(size: 56, weight: .bold, design: .rounded)

    /// Large metric inside a card.
    public static let metric = Font.system(size: 28, weight: .semibold, design: .rounded)

    /// Section title.
    public static let title = Font.system(.title2, design: .default, weight: .semibold)

    /// Card title.
    public static let cardTitle = Font.system(.headline, design: .default, weight: .semibold)

    /// Body copy and explanations.
    public static let body = Font.system(.body)

    /// Secondary detail: paths, timestamps, captions.
    public static let caption = Font.system(.caption)

    /// Monospaced path display, so long paths stay scannable.
    public static let path = Font.system(.caption, design: .monospaced)
}

extension View {
    /// Applies a numeric style that keeps digits from shifting as values change.
    ///
    /// Live metrics update every second (§8); proportional digits would make the whole card
    /// jitter.
    public func numericStyle(_ font: Font) -> some View {
        self.font(font).monospacedDigit()
    }
}
