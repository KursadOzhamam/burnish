import SwiftUI
import DesignSystem

/// Slow drifting particles behind the scan ring — CLAUDE.md §5.5.
///
/// `TimelineView` + `Canvas` keeps this off the view-update path, and positions are derived from
/// the timeline date rather than stored state, so there is nothing to keep in sync. Purely
/// decorative, so Reduce Motion removes it entirely (§5.3).
struct ScanParticleField: View {
    let palette: GradientPair

    @Environment(\.allowsDecorativeMotion) private var allowsDecorativeMotion

    /// One drifting dot.
    private struct Particle {
        /// Starting angle in degrees.
        let angle: Double
        /// Distance from centre as a fraction of the field's radius.
        let radius: Double
        /// Diameter in points.
        let size: Double
        /// Degrees per second.
        let speed: Double
    }

    /// Fixed layout so the field looks designed rather than noisy; only the phase animates.
    private static let particles: [Particle] = {
        var generator = SystemRandomNumberGenerator()
        return (0..<96).map { index in
            Particle(
                angle: Double(index) / 96 * 360 + Double.random(in: -8...8, using: &generator),
                radius: Double.random(in: 0.48...1.0, using: &generator),
                size: Double.random(in: 1.8...5.4, using: &generator),
                speed: Double.random(in: 0.05...0.20, using: &generator)
            )
        }
    }()

    var body: some View {
        if allowsDecorativeMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                Canvas { canvas, size in
                    let seconds = context.date.timeIntervalSinceReferenceDate
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let extent = min(size.width, size.height) / 2

                    for particle in Self.particles {
                        let angle = Angle.degrees(particle.angle + seconds * particle.speed * 60)
                        let distance = extent * particle.radius
                        let point = CGPoint(
                            x: center.x + cos(angle.radians) * distance,
                            y: center.y + sin(angle.radians) * distance
                        )
                        // Fade with distance so the field reads as depth, not as confetti.
                        let depth = 1 - particle.radius
                        let opacity = 0.22 + 0.46 * depth
                        let rect = CGRect(
                            x: point.x - particle.size / 2,
                            y: point.y - particle.size / 2,
                            width: particle.size,
                            height: particle.size
                        )
                        // Nearer particles take the warmer end of the gradient, which separates
                        // the layers far better than opacity alone.
                        let tint = depth > 0.5 ? palette.end.color : palette.start.color
                        let dot = Path(ellipseIn: rect)
                        canvas.fill(dot, with: .color(tint.opacity(opacity)))

                        // Soft halo on the closest particles only — enough to read as depth
                        // without turning the field into fog.
                        if depth > 0.62 {
                            let halo = rect.insetBy(dx: -particle.size * 1.6, dy: -particle.size * 1.6)
                            canvas.fill(
                                Path(ellipseIn: halo),
                                with: .radialGradient(
                                    Gradient(colors: [tint.opacity(0.18), .clear]),
                                    center: point,
                                    startRadius: 0,
                                    endRadius: halo.width / 2
                                )
                            )
                        }
                    }
                }
                // §5.5: heavy drawing is flattened so it stays at 60 fps.
                .drawingGroup()
            }
            .accessibilityHidden(true)
        }
    }
}
