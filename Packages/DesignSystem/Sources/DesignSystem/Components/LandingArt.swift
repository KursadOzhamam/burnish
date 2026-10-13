import SwiftUI

// MARK: Laptop illustration

/// The laptop drawn on the overview hero: a grey body, a violet screen with soft ellipses.
public struct LaptopIllustration: View {
    @Environment(\.colorScheme) private var scheme
    public init() {}

    public var body: some View {
        let dark = scheme == .dark
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(dark ? Color(white: 0.3) : Color(red: 0.86, green: 0.85, blue: 0.9))
                .overlay(alignment: .center) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(LinearGradient(
                            colors: dark ? [Color(red: 0.25, green: 0.2, blue: 0.4), Color(red: 0.4, green: 0.3, blue: 0.62)]
                                         : [Color(red: 0.95, green: 0.92, blue: 0.99), Color(red: 0.72, green: 0.62, blue: 0.9)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .padding(5)
                        .overlay {
                            ZStack {
                                Ellipse().fill(.white.opacity(0.35)).frame(width: 96, height: 70)
                                Ellipse().fill(.white.opacity(0.35)).frame(width: 52, height: 52)
                            }
                        }
                }
                .frame(width: 190, height: 124)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(dark ? Color(white: 0.38) : Color(red: 0.78, green: 0.77, blue: 0.84))
                .frame(width: 222, height: 9)
        }
        .accessibilityHidden(true)
    }
}

// MARK: Checkbox

/// The rounded violet checkbox of the design.
public struct BrandCheckbox: View {
    @Environment(\.colorScheme) private var scheme
    private let isOn: Bool
    private let toggle: () -> Void

    public init(isOn: Bool, toggle: @escaping () -> Void) {
        self.isOn = isOn
        self.toggle = toggle
    }

    public var body: some View {
        let t = scheme.theme
        Button(action: toggle) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isOn ? t.accent : t.card)
                .overlay { RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(isOn ? t.accent : t.cardBorder, lineWidth: 1.5) }
                .overlay { if isOn { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) } }
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(Text(isOn ? "1" : "0"))
    }
}
