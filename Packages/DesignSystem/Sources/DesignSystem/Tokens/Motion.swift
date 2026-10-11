import SwiftUI

/// Spring tokens — CLAUDE.md §5.3.
///
/// Durations live here only, so pacing can be retuned app-wide without touching call sites.
public enum Motion {
    /// Quick and precise: selection, toggles, hover.
    public static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.86)

    /// Calm and continuous: layout changes, card reveals, progress.
    public static let smooth = Animation.spring(response: 0.45, dampingFraction: 0.9)

    /// Playful overshoot, used sparingly: completion moments, counters landing.
    public static let bouncy = Animation.spring(response: 0.5, dampingFraction: 0.62)

    /// Stagger between sequentially revealed result cards (§5.5: 60 ms).
    public static let staggerInterval: Duration = .milliseconds(60)

    /// Substitute applied when Reduce Motion is on. Short enough to read as instant while
    /// still letting SwiftUI interpolate rather than snap.
    public static let reduced = Animation.easeOut(duration: 0.08)
}

/// Applies a motion token, degrading to `Motion.reduced` when Reduce Motion is enabled.
///
/// CLAUDE.md §5.3 requires decorative animation to simplify under Reduce Motion. Routing every
/// animation through this modifier means honouring that setting is the default rather than
/// something each view has to remember.
private struct MotionModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? Motion.reduced : animation, value: value)
    }
}

extension View {
    /// Animates changes to `value` using a `Motion` token, respecting Reduce Motion.
    public func motion<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

extension EnvironmentValues {
    /// Decorative animation — particles, pulses, breathing — should be dropped entirely rather
    /// than shortened when Reduce Motion is on.
    public var allowsDecorativeMotion: Bool {
        !accessibilityReduceMotion
    }
}
