import Testing
import SwiftUI
@testable import DesignSystem

@Suite("Spacing and radius scales")
struct ScaleTests {
    @Test("Spacing scale matches CLAUDE.md §5.3 exactly")
    func spacingScale() {
        #expect(Spacing.scale == [4, 8, 12, 16, 24, 32, 48])
    }

    @Test("Corner radius scale matches CLAUDE.md §5.3 exactly")
    func radiusScale() {
        #expect(CornerRadius.scale == [8, 14, 22, 32])
    }

    @Test("Both scales increase strictly, so no two tokens are interchangeable")
    func scalesAreStrictlyIncreasing() {
        #expect(zip(Spacing.scale, Spacing.scale.dropFirst()).allSatisfy { $0 < $1 })
        #expect(zip(CornerRadius.scale, CornerRadius.scale.dropFirst()).allSatisfy { $0 < $1 })
    }
}

@Suite("Motion tokens")
struct MotionTests {
    @Test("Stagger interval is the 60 ms specified in §5.5")
    func staggerInterval() {
        #expect(Motion.staggerInterval == .milliseconds(60))
    }
}

@Suite("RGB")
struct RGBTests {
    @Test("Hex decoding splits the channels correctly")
    func hexDecoding() {
        let red = RGB(hex: 0xFF0000)
        #expect(red.red == 1)
        #expect(red.green == 0)
        #expect(red.blue == 0)

        let teal = RGB(hex: 0x14B8A6)
        #expect(abs(teal.red - 20.0 / 255) < 0.001)
        #expect(abs(teal.green - 184.0 / 255) < 0.001)
        #expect(abs(teal.blue - 166.0 / 255) < 0.001)
    }

    @Test("Components outside 0...1 are clamped")
    func clamping() {
        let subject = RGB(-1, 2, 0.5)
        #expect(subject.red == 0)
        #expect(subject.green == 1)
        #expect(subject.blue == 0.5)
    }

    @Test("Luminance endpoints are correct")
    func luminanceEndpoints() {
        #expect(abs(RGB(hex: 0xFFFFFF).luminance - 1) < 0.001)
        #expect(abs(RGB(hex: 0x000000).luminance - 0) < 0.001)
    }

    @Test("Contrast of black against white is the WCAG maximum of 21:1")
    func maximumContrast() {
        let ratio = RGB(hex: 0x000000).contrastRatio(against: RGB(hex: 0xFFFFFF))
        #expect(abs(ratio - 21) < 0.01)
    }

    @Test("Contrast is symmetric")
    func contrastIsSymmetric() {
        let lhs = RGB(hex: 0x4F46E5)
        let rhs = RGB(hex: 0xFFFFFF)
        #expect(abs(lhs.contrastRatio(against: rhs) - rhs.contrastRatio(against: lhs)) < 0.000_1)
    }

    @Test("A colour has no contrast against itself")
    func selfContrast() {
        let subject = RGB(hex: 0x123456)
        #expect(abs(subject.contrastRatio(against: subject) - 1) < 0.000_1)
    }
}
