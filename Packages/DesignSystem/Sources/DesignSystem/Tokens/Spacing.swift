import Foundation

/// Spacing scale — CLAUDE.md §5.3: 4, 8, 12, 16, 24, 32, 48.
///
/// Layout code uses these names rather than raw numbers so the rhythm stays consistent and
/// adjustable from one place.
public enum Spacing {
    /// 4 pt — hairline gaps inside a control.
    public static let xxs: CGFloat = 4
    /// 8 pt — between tightly related elements.
    public static let xs: CGFloat = 8
    /// 12 pt — label to value.
    public static let small: CGFloat = 12
    /// 16 pt — default padding inside a card.
    public static let medium: CGFloat = 16
    /// 24 pt — between cards.
    public static let large: CGFloat = 24
    /// 32 pt — between groups.
    public static let xl: CGFloat = 32
    /// 48 pt — section separation. §5.1 asks for generous whitespace.
    public static let xxl: CGFloat = 48

    /// The scale in order, for tests and documentation.
    public static let scale: [CGFloat] = [xxs, xs, small, medium, large, xl, xxl]
}

/// Corner radii — CLAUDE.md §5.3: 8, 14, 22, 32.
public enum CornerRadius {
    /// 8 pt — small controls, chips.
    public static let small: CGFloat = 8
    /// 14 pt — rows, inner containers.
    public static let medium: CGFloat = 14
    /// 22 pt — cards. The workhorse value.
    public static let large: CGFloat = 22
    /// 32 pt — hero containers and sheets.
    public static let xl: CGFloat = 32

    public static let scale: [CGFloat] = [small, medium, large, xl]
}
